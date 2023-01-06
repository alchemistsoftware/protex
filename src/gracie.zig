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

const cat_box = struct
{
    Name: []u8,
    MainPyModuleIndex: usize,
    StartPatternID: c_uint,
    EndPatternID: c_uint,
};

const extractor_def = struct
{
    Name: []u8,
    Country: [2]u8,
    Language: [2]u8,

    CatBoxes: []cat_box,
    Database: ?*c.hs_database_t,
    nDatabaseBytes: usize,
};

Scratch: ?*c.hs_scratch_t,
Ally: allocator,
FBackBuf: []u8,

ExtrDefs: []extractor_def,
PyCallbacks: array_list(sempy.callback_fn), //TODO(cjb): slice of py callbacks

//
// Possible status codes that may be returned during calls to C api.
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

pub fn Init(Ally: allocator, ArtifactPathZ: ?[* :0]const u8) !self
{
    var Self: self = undefined;
    Self.Ally = Ally;

    // Open artifact file and obtain header in order to begin parsing.
    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }

    const ArtiF = try std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{});
    defer ArtiF.close();

    const R = ArtiF.reader();
    const ArtiHeader = try R.readStruct(common.arti_header);

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
        const PyModHeader = try R.readStruct(common.arti_py_module_header);

        // NameZ buf & code buf
        var NameZ = try Self.Ally.alloc(u8, PyModHeader.nPyNameBytes + 1);
        defer Self.Ally.free(NameZ);
        var SourceZ = try Self.Ally.alloc(u8, PyModHeader.nPySourceBytes + 1);
        defer Self.Ally.free(SourceZ);

        // Read name & code
        debug.assert(try R.readAll(NameZ[0 .. PyModHeader.nPyNameBytes]) ==
            PyModHeader.nPyNameBytes);
        debug.assert(try R.readAll(SourceZ[0 .. PyModHeader.nPySourceBytes]) ==
            PyModHeader.nPySourceBytes);

        // Null terminate both name & code buffers.
        NameZ[NameZ.len - 1] = 0;
        SourceZ[SourceZ.len - 1] = 0;

        // Attempt to load module & append to module list.
        const CallbackFn = try sempy.LoadModuleFromSource(NameZ, SourceZ);
        try Self.PyCallbacks.append(CallbackFn);
    }

//
// Read extractor definitions
//
    Self.ExtrDefs = try Self.Ally.alloc(extractor_def, ArtiHeader.nExtractorDefs);

    var ExtractorDefIndex: usize = 0;
    while (ExtractorDefIndex < ArtiHeader.nExtractorDefs) : (ExtractorDefIndex += 1)
    {
        const DefHeader = try R.readStruct(common.arti_def_header);
        var ExtrDef: extractor_def = undefined;

        // Read country, language, and name
        debug.assert(try R.readAll(&ExtrDef.Country) == 2);
        debug.assert(try R.readAll(&ExtrDef.Language) == 2);
        ExtrDef.Name = try Self.Ally.alloc(u8, DefHeader.nExtractorNameBytes);
        debug.assert(try R.readAll(ExtrDef.Name) == DefHeader.nExtractorNameBytes);

        // Read serialized database NOTE(cjb): Can I just pass this to deserailze at instead of
        // allocing a buffer then passing?
        var SerializedBytes = try Self.Ally.alloc(u8, DefHeader.DatabaseSize);
        defer Self.Ally.free(SerializedBytes);
        debug.assert(try R.readAll(SerializedBytes) == DefHeader.DatabaseSize);

        // TODO(cjb): hs_set_misc_allocator():
            //var HSAlloc: c.hs_alloc_t = Bannans;
            //var HSFree: c.hs_free_t = Bannans2;
            // typedef void *(*hs_alloc_t)(size_t size)
            // typedef void (*hs_free_t)(void *ptr)
            // hs_error_t hs_set_allocator(hs_alloc_t alloc_func, hs_free_t free_func)

        var DatabaseBuf = try Self.Ally.alloc(u8, DefHeader.DatabaseSize);
        ExtrDef.Database = @ptrCast(*c.hs_database_t, @alignCast(@alignOf(c.hs_database_t),
                DatabaseBuf.ptr));
        ExtrDef.nDatabaseBytes = DefHeader.DatabaseSize;
        try HSCodeToErr(c.hs_deserialize_database_at(SerializedBytes.ptr, DefHeader.DatabaseSize,
            ExtrDef.Database));

        // TODO(cjb): set allocator used for scratch
        Self.Scratch = null;
        try HSCodeToErr(c.hs_alloc_scratch(ExtrDef.Database, &Self.Scratch));

//
// Read category data
//
        ExtrDef.CatBoxes = try Self.Ally.alloc(cat_box, DefHeader.nCategories);

        var PatternSum: usize = 0;
        var CatIndex: usize = 0;
        while (CatIndex < DefHeader.nCategories) : (CatIndex += 1)
        {
            const CatHeader = try R.readStruct(common.arti_cat_header);

            // Category name
            var Name = try Ally.alloc(u8, CatHeader.nCategoryNameBytes);
            debug.assert(try R.readAll(Name) == CatHeader.nCategoryNameBytes);

            // Pattern count
            var nPatternsForCategory: usize = undefined;
            debug.assert(try R.readAll(@ptrCast([*]u8, &nPatternsForCategory)
                    [0 .. @sizeOf(usize)]) == @sizeOf(usize));
            PatternSum += nPatternsForCategory;

            // Mainpy module index
            var MainPyModuleIndex: usize = undefined;
            debug.assert(try R.readAll(@ptrCast([*]u8, &MainPyModuleIndex)
                    [0 .. @sizeOf(usize)]) == @sizeOf(usize));

           ExtrDef.CatBoxes[CatIndex] = cat_box{
               .Name = Name,
               .MainPyModuleIndex = MainPyModuleIndex,
               .StartPatternID = @intCast(c_uint, PatternSum - nPatternsForCategory),
               .EndPatternID = @intCast(c_uint, PatternSum),
           };
        }

        Self.ExtrDefs[ExtractorDefIndex] = ExtrDef;
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
    nTextBytes: c_uint, Result: ?*[*]u8, nBytesCopied: ?*c_uint) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    var ExtractResult = Extract(Self.?.*.?, Text.?[0 .. nTextBytes]) catch |Err|
        return ErrToCode(Err);

    nBytesCopied.?.* = @intCast(c_uint, ExtractResult.len);
    Result.?.* = @ptrCast([*]u8, ExtractResult.ptr);
    return GRACIE_SUCCESS;
}

pub fn Extract(Self: *self, Text: []const u8) ![]u8
{
    // Initialize fixed buffer allocator from scratch space.
    var FBAlly = fixed_buffer_allocator.init(Self.FBackBuf);

    // Init MatchList
    var MatchList = array_list(match).init(FBAlly.allocator());

    // Allocate buffer for SempyRun output
    var SempyRunBuf = try FBAlly.allocator().alloc(u8, 1024*1);

    var Parser = std.json.Parser.init(FBAlly.allocator(), false); // Copy strings = false
    var ReturnBuf: []u8 = try FBAlly.allocator().alloc(u8, 1024*2); // 2kib for json buffer
    var SliceStream = std.io.fixedBufferStream(ReturnBuf);
    var W = std.json.writeStream(SliceStream.writer(), 5);
    try W.beginObject();

    for (Self.ExtrDefs) |Def|
    {
        var nBytesCopied: usize = 0;
        MatchList.clearRetainingCapacity();
        Parser.reset();

        // Hyperscannnnn!!
        try HSCodeToErr(c.hs_scan(Def.Database, Text.ptr, @intCast(c_uint, Text.len), 0, Self.Scratch,
                EventHandler, &MatchList));
        for (MatchList.items) |M|
        {
            var MainModuleIndex: usize = undefined;
            for (Def.CatBoxes) |Cat|
            {
                if ((M.ID >= Cat.StartPatternID) and
                    (M.ID < Cat.EndPatternID))
                {
                    MainModuleIndex = Cat.MainPyModuleIndex;
                }
            }
            // TODO(cjb): Have sempy alloc a buffer for you.
            nBytesCopied = try sempy.Run(Self.PyCallbacks.items[MainModuleIndex],
                Text[M.SO .. M.EO], SempyRunBuf);
            break;
        }
        try W.objectField(Def.Name);

        // Verify writing a valid json string
        if (std.json.validate(@ptrCast([*]const u8, SempyRunBuf.ptr)[0 .. nBytesCopied]))
        {
            const ParseTree = try Parser.parse(SempyRunBuf[0..nBytesCopied]);
            const RootJsonObj = ParseTree.root;
            try W.emitJson(RootJsonObj);
        }
        else
        {
            try W.emitString("Bad json");
        }
    }
    try W.endObject();

    return SliceStream.getWritten();
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
    HSCodeToErr(c.hs_free_scratch(Self.Scratch)) catch unreachable;

    Self.Ally.free(Self.FBackBuf);

    for (Self.ExtrDefs) |Def|
    {
        Self.Ally.free(Def.Name);
        for (Def.CatBoxes) |Cat| Self.Ally.free(Cat.Name);
        Self.Ally.free(Def.CatBoxes);
        Self.Ally.free(@ptrCast([*]u8, Def.Database.?)[0 .. Def.nDatabaseBytes]);
    }
    Self.Ally.free(Self.ExtrDefs);

    // TODO(cjb): Have sempy own PyCallbacks array list
    for (Self.PyCallbacks.items) |CB| sempy.UnloadCallbackFn(CB);
    Self.PyCallbacks.deinit();

    // Deinitialize sempy
    sempy.Deinit();
}

test "Gracie C"
{
    var G: ?*anyopaque = undefined;
    var Result: [*]u8 = undefined;
    var nBytesCopied: c_uint = undefined;
    const Text = "Earn $30 an hour";

    debug.assert(GracieInit(&G, "./data/gracie.bin") == GRACIE_SUCCESS);
    debug.assert(GracieExtract(&G, Text, Text.len, &Result, &nBytesCopied) == GRACIE_SUCCESS);
    debug.assert(GracieDeinit(&G) == GRACIE_SUCCESS);
}

test "Gracie"
{
    var Ally = std.testing.allocator;
    var G = try self.Init(Ally, "./data/gracie.bin");
    _ = try self.Extract(&G, "Earn $30 an hour"); // TODO(cjb): Print this..
    self.Deinit(&G);
}
