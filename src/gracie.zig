const std = @import("std");
const slab_allocator = @import("slab_allocator.zig");
const common = @import("common.zig");
const sempy = @import("sempy.zig");
const c = @cImport({
    @cInclude("hs.h");
});

const debug = std.debug;
const allocator = std.mem.Allocator;
const fixed_buffer_allocator = std.heap.FixedBufferAllocator;
const array_list = std.ArrayList;

const self = @This();

// NOTE(cjb): Keep in mind this will need to be exposed at some point or another.
const match = struct
{
    SO: c_ulonglong,
    EO: c_ulonglong,
    ID: c_uint,
};

// TODO(cjb): Loaded extractors buf...
const cat_box = struct
{
    CategoryName: []u8,
    MainPyModuleIndex: usize,
    StartPatternID: c_uint,
    EndPatternID: c_uint, // Exclusive
};

Database: ?*c.hs_database_t,
nDatabaseBytes: usize,
Scratch: ?*c.hs_scratch_t,
Ally: allocator,
FBackBuf: []u8,

CatBoxes: array_list(cat_box),
PyCallbacks: array_list(sempy.callback_fn),
//
// Possible status codes that may be returned during gracie calls.
//

/// Call was executed successfully
pub const GRACIE_SUCCESS: c_int = 0;

/// Bad paramater was passed
pub const GRACIE_INVALID: c_int = -1;

/// Unhandled internal error
pub const GRACIE_UNKNOWN_ERROR: c_int = -2;

/// A memory allocation failed
pub const GRACIE_NOMEM: c_int = -3;

/// Maps hyperscan status codes to an eqv. error. This way we may take advantage of zig's err
/// handling system.
fn HSCodeToErr(ReturnCode: c_int) !void
{
    if (ReturnCode != c.HS_SUCCESS)
    {
        switch (ReturnCode) {
            c.HS_INVALID => return error.HSInvalid,
            c.HS_NOMEM => return error.HSNoMem,
            c.HS_SCAN_TERMINATED => return error.HSScanTerminated,
            c.HS_COMPILER_ERROR => return error.HSCompiler,
            c.HS_DB_VERSION_ERROR => return error.HSDBVersion,
            c.HS_DB_PLATFORM_ERROR => return error.HSDBPlatform,
            c.HS_DB_MODE_ERROR => return error.HSDBMode,
            c.HS_BAD_ALIGN => return error.HSBadAlign,
            c.HS_BAD_ALLOC => return error.HSBadAlloc,
            c.HS_SCRATCH_IN_USE => return error.HSScratchInUse,
            c.HS_ARCH_ERROR => return error.HSArch,
            c.HS_INSUFFICIENT_SPACE => return error.HSInsufficientSpace,
            c.HS_UNKNOWN_ERROR => return error.HSUnknown,
            else => unreachable,
        }
    }
}

/// Convert zig errs to status code.
fn ErrToCode(Err: anyerror) c_int
{
    std.log.err("{}", .{Err});
    switch(Err)
    {
        error.OutOfMemory => return GRACIE_NOMEM,
        error.FileNotFound => return GRACIE_INVALID,
        error.HSInvalid,
        error.HSNoMem,
        error.HSScanTerminated,
        error.HSCompiler,
        error.HSDBVersion,
        error.HSDBPlatform,
        error.HSDBMode,
        error.HSBadAlign,
        error.HSBadAlloc,
        error.HSScratchInUse,
        error.HSArch,
        error.HSInsufficientSpace,
        error.HSUnknown,
        error.SempyInvalid,
        error.SempyConvertArgs,
        error.SempyUnknown => return GRACIE_UNKNOWN_ERROR,
        else => unreachable,
    }
}

export fn GracieInit(Ctx: ?*?*anyopaque, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    var Ally = std.heap.page_allocator;
    Self.?.* = Ally.create(self) catch |Err|
        return ErrToCode(Err);
    Self.?.*.?.* = Init(Ally, ArtifactPathZ) catch |Err|
        return ErrToCode(Err);
    return GRACIE_SUCCESS;
}

pub fn Init(Ally: allocator, ArtifactPathZ: ?[*:0]const u8) !self
{
    var Self: self = undefined;
    Self.Ally = Ally;

//
// Deserialize artifact
//
    // Open artifact file
    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }
    const ArtiF = try std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{});

    // Read artifact header
    const ArtiHeader = try ArtiF.reader().readStruct(common.arti_header);

//
// Read python module data and pass it to sempy for loading.
//
    // Sempy must be initialized before any sempy fns are called.
    try sempy.Init();

    // Future sempy run calls will require module name so we will store them here.
    Self.PyCallbacks = array_list(sempy.callback_fn).init(Self.Ally);

    var PyModIndex: usize = 0;
    while (PyModIndex < ArtiHeader.nPyModules) : (PyModIndex += 1)
    {
        const PyModHeader = try ArtiF.reader().readStruct(common.arti_py_module_header);

        // NameZ buf & code buf
        var NameZ = try Self.Ally.alloc(u8, PyModHeader.nPyNameBytes + 1);
        defer Self.Ally.free(NameZ);
        var SourceZ = try Self.Ally.alloc(u8, PyModHeader.nPySourceBytes + 1);
        defer Self.Ally.free(SourceZ);

        // Read name & code
        debug.assert(try ArtiF.readAll(NameZ[0 .. PyModHeader.nPyNameBytes]) ==
            PyModHeader.nPyNameBytes);
        debug.assert(try ArtiF.readAll(SourceZ[0 .. PyModHeader.nPySourceBytes]) ==
            PyModHeader.nPySourceBytes);

        // Null terminate both name & code buffers.
        NameZ[NameZ.len - 1] = 0;
        SourceZ[SourceZ.len - 1] = 0;

        // Attempt to load module & append to module list.
        const CallbackFn = try sempy.LoadModuleFromSource(NameZ, SourceZ);
        try Self.PyCallbacks.append(CallbackFn);
    }

    // Read n extractor definitions
    var ExtractorDefIndex: usize = 0;
    while (ExtractorDefIndex < ArtiHeader.nExtractorDefs) : (ExtractorDefIndex += 1)
    {
        // Read definition header
        const DefHeader = try ArtiF.reader().readStruct(common.arti_def_header);

        // TODO(cjb): Store these values somewhere
        var Country: [2]u8 = undefined;
        var Language: [2]u8 = undefined;
        try ArtiF.reader().skipBytes(Language.len + Country.len + DefHeader.nExtractorNameBytes, .{});

        // Read serialized database
        var SerializedBytes = try Self.Ally.alloc(u8, DefHeader.DatabaseSize);
        defer Self.Ally.free(SerializedBytes);
        debug.assert(try ArtiF.reader().readAll(SerializedBytes) == DefHeader.DatabaseSize);

        // TODO(cjb): hs_set_misc_allocator():
            //var HSAlloc: c.hs_alloc_t = Bannans;
            //var HSFree: c.hs_free_t = Bannans2;
            // typedef void *(*hs_alloc_t)(size_t size)
            // typedef void (*hs_free_t)(void *ptr)
            // hs_error_t hs_set_allocator(hs_alloc_t alloc_func, hs_free_t free_func)

        var DatabaseBuf = try Self.Ally.alloc(u8, DefHeader.DatabaseSize);
        Self.Database = @ptrCast(*c.hs_database_t, @alignCast(@alignOf(c.hs_database_t),
                DatabaseBuf.ptr));
        Self.nDatabaseBytes = DefHeader.DatabaseSize;
        try HSCodeToErr(c.hs_deserialize_database_at(SerializedBytes.ptr, SerializedBytes.len,
            Self.Database));

        // TODO(cjb): set allocator used for scratch
        Self.Scratch = null;
        try HSCodeToErr(c.hs_alloc_scratch(Self.Database, &Self.Scratch));

//
// Read category data
//
        Self.CatBoxes = array_list(cat_box).init(Ally);

        var PatternSum: usize = 0;
        var CatIndex: usize = 0;
        while (CatIndex < DefHeader.nCategories) : (CatIndex += 1)
        {
            const CatHeader = try ArtiF.reader().readStruct(common.arti_cat_header);

            // Category name
            var CategoryName = try Ally.alloc(u8, CatHeader.nCategoryNameBytes);
            debug.assert(try ArtiF.readAll(CategoryName) == CatHeader.nCategoryNameBytes);

            // Pattern count
            var nPatternsForCategory: usize = undefined;
            debug.assert(try ArtiF.readAll(@ptrCast([*]u8, &nPatternsForCategory)
                    [0 .. @sizeOf(usize)]) == @sizeOf(usize));
            PatternSum += nPatternsForCategory;

            // Mainpy module index
            var MainPyModuleIndex: usize = undefined;
            debug.assert(try ArtiF.readAll(@ptrCast([*]u8, &MainPyModuleIndex)
                    [0 .. @sizeOf(usize)]) == @sizeOf(usize));

           try Self.CatBoxes.append(cat_box{
               .CategoryName = CategoryName,
               .MainPyModuleIndex = MainPyModuleIndex,
               .StartPatternID = @intCast(c_uint, PatternSum - nPatternsForCategory),
               .EndPatternID = @intCast(c_uint, PatternSum),
           });
        }
    }

    // Initialize extractor scratch buffer
    Self.FBackBuf = try Ally.alloc(u8, 1024*20);

    return Self;
}

fn EventHandler(ID: c_uint, From: c_ulonglong, To: c_ulonglong, _: c_uint,
    Ctx: ?*anyopaque) callconv(.C) c_int
{
    const MatchList = @ptrCast(?*array_list(match),
        @alignCast(@alignOf(?*array_list(match)), Ctx)) orelse unreachable;
    if (MatchList.items.len + 1 > MatchList.capacity)
    {
        // TODO(cjb): Decide if this should be handled or not.
        MatchList.append(.{.SO=From, .EO=To, .ID=ID}) catch unreachable;
        return 0;
    }
    else
    {
        unreachable; //TODO(cjb): Grow matchlist...
    }
    return 1;
}

export fn GracieExtract(Ctx: ?*?*anyopaque, Text: ?[*]const u8,
    nTextBytes: c_uint, Result: ?*[*]c_uint, n32sCopied: ?*c_uint) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    var ExtractResult = Extract(Self.?.*.?, Text.?[0 .. nTextBytes]) catch |Err|
        return ErrToCode(Err);

    n32sCopied.?.* = @intCast(c_uint, ExtractResult.len);
    Result.?.* = @ptrCast([*]c_uint, ExtractResult.ptr);
    return GRACIE_SUCCESS;
}

pub fn Extract(Self: *self, Text: []const u8) ![]u32
{
    // Initialize fixed buffer allocator from scratch space.
    var FBufAlly = fixed_buffer_allocator.init(Self.FBackBuf);

    // Init MatchList
    var MatchList = array_list(match).init(FBufAlly.allocator());

    var Result: []u32 = try FBufAlly.allocator().alloc(u32, 1024*2); // 2kib for result
    var n32sCopied: usize = 0;

    // Hyperscannnnn!!
    try HSCodeToErr(c.hs_scan(Self.Database, Text.ptr, @intCast(c_uint, Text.len), 0, Self.Scratch,
            EventHandler, &MatchList));
    for (MatchList.items) |M|
    {
        var MainModuleIndex: usize = undefined;
        for (Self.CatBoxes.items) |Cat|
        {
            if ((M.ID >= Cat.StartPatternID) and
                (M.ID < Cat.EndPatternID))
            {
                MainModuleIndex = Cat.MainPyModuleIndex;
            }
        }
        n32sCopied = try sempy.Run(Self.PyCallbacks.items[MainModuleIndex],
            Text[M.SO .. M.EO], Result);
        break;
    }

    var ResultResult: []u8 = try FBufAlly.allocator().alloc(u8, 1024*2); // 2kib for result
    var SliceStream = std.io.fixedBufferStream(ResultResult);
    var W = std.json.writeStream(SliceStream.writer(), 10);

    try W.beginObject();
    try W.objectField("Output");
    try W.emitString(@ptrCast([*]const u8, Result.ptr)[0 .. n32sCopied*4]);
    try W.endObject();

    const Foo = SliceStream.getWritten();
    //std.debug.print("got codepoint {s}\n", .{Foo});
    //var Utf8Iter = (try std.unicode.Utf8View.init(
    //        @ptrCast([*]const u8, Foo.ptr)[0 .. n32sCopied*4])).iterator();
    //while (Utf8Iter.nextCodepointSlice()) |Codepoint|
    //{
    //    std.debug.print("got codepoint {s}\n", .{Codepoint});
    //}
    return Result[0 .. n32sCopied]; // SliceStream.getWritten();
}

export fn GracieDeinit(Ctx: ?*?*anyopaque) callconv(.C) c_int
{
    const Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    Deinit(Self.?.*.?);
    Self.?.*.?.Ally.destroy(Self.?.*.?);
    return GRACIE_SUCCESS;
}

pub fn Deinit(Self: *self) void
{
    // Free hs scratch and database
    HSCodeToErr(c.hs_free_scratch(Self.Scratch)) catch unreachable;
    Self.Ally.free(@ptrCast([*]u8, Self.Database.?)[0 .. Self.nDatabaseBytes]);

    Self.Ally.free(Self.FBackBuf);

    for (Self.CatBoxes.items) |Cat| Self.Ally.free(Cat.CategoryName);
    Self.CatBoxes.deinit();

    // TODO(cjb): Have sempy own PyCallbacks array list
    for (Self.PyCallbacks.items) |CB| sempy.UnloadCallbackFn(CB);
    Self.PyCallbacks.deinit();

    // Deinitialize sempy
    sempy.Deinit();
}

test "Gracie C"
{
    var G: ?*anyopaque = undefined;
    var Result: [*]c_uint = undefined;
    var n32sCopied: c_uint = undefined;
    const Text = "Earn $30 an hour";

    debug.assert(GracieInit(&G, "./data/gracie.bin") == GRACIE_SUCCESS);
    debug.assert(GracieExtract(&G, Text, Text.len, &Result, &n32sCopied) == GRACIE_SUCCESS);
    debug.assert(GracieDeinit(&G) == GRACIE_SUCCESS);
}

test "Gracie"
{
    var Ally = std.testing.allocator;
    var G = try self.Init(Ally, "./data/gracie.bin");
    _ = try self.Extract(&G, "Earn $30 an hour"); // TODO(cjb): Print this..
    self.Deinit(&G);
}
