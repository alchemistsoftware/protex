const std = @import("std");
const slab_allocator = @import("slab_allocator.zig");
const common = @import("common.zig");
const sempy = @import("sempy.zig");
const c = @cImport({
    @cInclude("hs.h");
});

const debug = std.debug;
const allocator = std.mem.Allocator;
const array_list = std.ArrayList;

const self = @This();

// NOTE(cjb): Keep in mind this will need to be exposed at some point or another.
const gracie_match = struct
{
    SO: c_ulonglong,
    EO: c_ulonglong,
    CatID: c_uint,
};

const loaded_py_module = struct
{
//    ModName: []u8,
    CatName: []u8,
    CatID: c_uint,
};

// TODO(cjb): Loaded extractors buf...

Database: ?*c.hs_database_t,
Scratch: ?*c.hs_scratch_t,
Ally: allocator,

//ManagedVT: gracie_managed_vtable,

/// List of category ids, where pattern id is the index of the associated category id.
CatIDs: array_list(c_uint),
MatchList: array_list(gracie_match), // TODO(cjb): Benchmark init. of this data strcuture within
                                     // extract call instead of GracieInit
LoadedPyModules: array_list(loaded_py_module),
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

//const gracie_free_fn = *const fn(Ptr: ?*anyopaque) callconv(.C) void;
//const gracie_resize_fn = *const fn(Ptr: ?*anyopaque, Size: usize) callconv(.C) ?*anyopaque;
//
//const gracie_managed_vtable = extern struct
//{
//    Alloc: gracie_alloc_fn,
//    Free: gracie_free_fn,
//    Resize: gracie_resize_fn,
//};

//
// Allocator compatable vtable functions for calling c memory procedures *mostly* ripped straight
// from the zig std library.
//

//fn ManagedAlloc(Ctx: *anyopaque, Len: usize, Log2PtrAlign: u8, RetAddr: usize) ?[*]u8
//{
//    _ = RetAddr;
//    debug.assert(Log2PtrAlign <= comptime std.math.log2_int(usize, @alignOf(std.c.max_align_t)));
//    const VT = @ptrCast(*gracie_managed_vtable, @alignCast(@alignOf(gracie_managed_vtable), Ctx));
//    return @ptrCast(?[*]u8, VT.Alloc(Len));
//}
//
//fn GetRecordPtr(Buf: []u8) *align(1) usize
//{
//    return @intToPtr(*align(1) usize, @ptrToInt(Buf.ptr) + Buf.len);
//}
//
//fn ManagedResize(Ctx: *anyopaque, Buf: []u8, Log2OldAlign: u8, NewLen: usize, RetAddr: usize) ?[*]u8
//{
//    _ = Log2OldAlign;
//    _ = RetAddr;
//    const VT = @ptrCast(*gracie_managed_vtable, @alignCast(@alignOf(gracie_managed_vtable), Ctx));
//
//    return @ptrCast(?[*]u8, VT.Resize(Buf.ptr, NewLen));
//    assert(new_ptr == @intToPtr(*anyopaque, root_addr));
//    getRecordPtr(buf.ptr[0..new_size]).* = root_addr;
//}
//
//fn ManagedFree(Ctx: *anyopaque, Buf: []u8, Log2OldAlign: u8, NewLen: usize, RetAddr: usize) void
//{
//    _ = Log2OldAlign;
//    _ = RetAddr;
//    _ = NewLen;
//    const VT = @ptrCast(*gracie_managed_vtable, @alignCast(@alignOf(gracie_managed_vtable), Ctx));
//    VT.Free(Buf.ptr);
//}
//export fn GracieManagedInit(Ctx: ?*?*anyopaque, Alloc: gracie_alloc_fn, Free: gracie_free_fn,
//    Resize: gracie_resize_fn, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
//{
//    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
//
//    // Stack allocator from stack vtable
//    var SVT = gracie_managed_vtable{
//        .Alloc = Alloc,
//        .Resize= Resize,
//        .Free = Free,
//    };
//    var SAlly = allocator{
//        .ptr = @ptrCast(*anyopaque, &SVT),
//        .vtable = &.{
//            .alloc = ManagedAlloc,
//            .resize = ManagedResize,
//            .free = ManagedFree,
//        },
//    };
//
//    // Perform managed alloc storing result of self.Init in allocated slot.
//    var SelfBytes = ManagedAlloc(&SVT, @sizeOf(self), @sizeOf(*void * 2), 0);
//    Self.?.* = @ptrCast(?*self, @alignCast(@alignOf(self), SelfBytes));
//    Self.?.* orelse return GRACIE_NOMEM; // Check to see if actually alloc'd.
//    Self.?.*.?.* = Init(Ctx, SAlly, ArtifactPathZ) catch |Err|
//        return ErrToCode(Err);
//
//    // Copy stack allocated vtable to new Self's vtable then update stack allocated allocator's
//    //  pointer to point to Self's vtable (just copied) instead of the original.
//    Self.ManagedVT = SVT;
//    Self.Ally.ptr = &Self.ManagedVT;
//
//    return GRACIE_SUCCESS;
//}

export fn GracieInit(Ctx: ?*?*anyopaque, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    var Ally = std.heap.c_allocator;
    Self.?.* = Ally.create(self) catch |Err|
        return ErrToCode(Err);
    Self.?.*.?.* = Init(Ally, ArtifactPathZ) catch |Err|
        return ErrToCode(Err);
    return GRACIE_SUCCESS;
}

pub fn Init(Ally: allocator, ArtifactPathZ: ?[*:0]const u8) !self
{
    var Self: self = undefined;

    // Copy alloactor
    Self.Ally = Ally;

    // Initialize sempy ( this must be initialized before any sempy fns are called. )
    try sempy.Init();

    // Initialize list to keep track of loaded sempy modules.
    Self.LoadedPyModules = array_list(loaded_py_module).init(Self.Ally);

//
// Deserialize artifact
//
    // Open artifact file
    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }
    const ArtiF = try std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{});

    // Read artifact header
    const ArtiHeader = try ArtiF.reader().readStruct(common.gracie_arti_header);

    // Read n extractor definitions
    var ExtractorDefIndex: usize = 0;
    while (ExtractorDefIndex < ArtiHeader.nExtractorDefs) : (ExtractorDefIndex += 1)
    {
        // Read definition header
        const DefHeader = try ArtiF.reader().readStruct(common.gracie_extractor_def_header);

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

        try HSCodeToErr(c.hs_deserialize_database_at(SerializedBytes.ptr, SerializedBytes.len,
            Self.Database));

        // TODO(cjb): set allocator used for scratch
        Self.Scratch = null;
        try HSCodeToErr(c.hs_alloc_scratch(Self.Database, &Self.Scratch));

//
// Initialize category id's & load py modules
//
        Self.CatIDs = array_list(c_uint).init(Self.Ally);
        var CatIndex: usize = 0;
        while (CatIndex < DefHeader.nCategories) : (CatIndex += 1)
        {
            // Read category header
            const CatHeader = try ArtiF.reader().readStruct(common.gracie_extractor_cat_header);

            // Record new module
            var LMod = loaded_py_module{
                //.ModName= TODO(cjb): Track module name
                .CatName = try Self.Ally.alloc(u8, CatHeader.nCategoryNameBytes + 1),
                .CatID = @intCast(c_uint, CatIndex),
            };
            debug.assert(try ArtiF.readAll(LMod.CatName[0 .. CatHeader.nCategoryNameBytes]) ==
                CatHeader.nCategoryNameBytes);
            LMod.CatName[CatHeader.nCategoryNameBytes] = 0;
            try Self.LoadedPyModules.append(LMod);

            var PatternIndex: usize = 0;
            while (PatternIndex < CatHeader.nPatterns) : (PatternIndex += 1)
            {
                try Self.CatIDs.append(@intCast(c_uint, CatIndex));
            }

            // Read module's source code
            var ModSourceCode = try Self.Ally.alloc(u8, CatHeader.nPyPluginSourceBytes + 1);
            defer Self.Ally.free(ModSourceCode); // We don't need to keep this around.
            debug.assert(try ArtiF.readAll(ModSourceCode[0 .. CatHeader.nPyPluginSourceBytes]) ==
                CatHeader.nPyPluginSourceBytes);
            ModSourceCode[CatHeader.nPyPluginSourceBytes] = 0;

            // Load sempy module
            var SMCtx = sempy.module_ctx{
                .Source=ModSourceCode[0..ModSourceCode.len - 1 :0],
                .Name=LMod.CatName[0..LMod.CatName.len - 1 :0],
            };
            try sempy.LoadModuleFromSource(&SMCtx);
        }
    }

    // Initialize match list
    Self.MatchList = array_list(gracie_match).init(Self.Ally);

    return Self;
}

fn EventHandler(ID: c_uint, From: c_ulonglong, To: c_ulonglong, _: c_uint,
    Ctx: ?*anyopaque) callconv(.C) c_int
{
    const This = @ptrCast(?*self, @alignCast(@alignOf(?*self), Ctx)) orelse unreachable;
    if (This.MatchList.items.len + 1 > This.MatchList.capacity)
    {
        // NOTE(cjb): Should an error be thrown here?
        This.MatchList.append(.{.SO=From, .EO=To, .CatID=This.CatIDs.items[ID]}) catch unreachable;
        return 0;
    }
    return 1;
}

export fn GracieExtract(Ctx: ?*?*anyopaque, Text: ?[*]u8, nTextBytes: c_uint) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    Extract(Self.?.*.?, Text, nTextBytes) catch |Err|
        return ErrToCode(Err);
    return GRACIE_SUCCESS;
}

pub fn Extract(Self: *self, Text: ?[*]u8, nTextBytes: c_uint) !void
{
    // Reset stuff
    Self.MatchList.clearRetainingCapacity();

    // Hyperscannnnn!!
    try HSCodeToErr(c.hs_scan(Self.Database, Text, nTextBytes, 0, Self.Scratch,
            EventHandler, Self));
    for (Self.MatchList.items) |M|
    {
        try sempy.RunModule(Text.?[M.SO .. M.EO], M.CatID);
    }
}

export fn GracieDeinit(Ctx: ?*?*anyopaque) callconv(.C) c_int
{
    const Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    Deinit(Self.?.*.?) catch |Err|
        return ErrToCode(Err);
    Self.?.*.?.Ally.destroy(Self.?.*.?);
    return GRACIE_SUCCESS;
}

pub fn Deinit(Self: *self) !void
{
    // Free hs scratch
    try HSCodeToErr(c.hs_free_scratch(Self.Scratch));

    // Deinitialize sempy
    try sempy.Deinit();
}

test "Gracie"
{
    var GracieCtx: ?*anyopaque = null;
    try std.testing.expect(
        self.Init(&GracieCtx, "./data/gracie.bin") ==
        GRACIE_SUCCESS);
    try std.testing.expect(
        self.Deinit(&GracieCtx) ==
        GRACIE_SUCCESS);
}
