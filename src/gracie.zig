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
    NameZ: []u8,
    CatID: c_uint,
};

// TODO(cjb): Loaded extractors buf...

Database: ?*c.hs_database_t,
nDatabaseBytes: usize,
Scratch: ?*c.hs_scratch_t,
Ally: allocator,

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
        Self.nDatabaseBytes = DefHeader.DatabaseSize;
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
            try ArtiF.reader().skipBytes(CatHeader.nCategoryNameBytes, .{});

            // Record new module
            var LMod = loaded_py_module{
                .NameZ = try Self.Ally.alloc(u8, CatHeader.nPyNameBytes + 1),
                .CatID = @intCast(c_uint, CatIndex),
            };
            debug.assert(try ArtiF.readAll(
                    LMod.NameZ[0 .. CatHeader.nPyNameBytes]) == CatHeader.nPyNameBytes);
            LMod.NameZ[LMod.NameZ.len - 1] = 0;

            var PatternIndex: usize = 0;
            while (PatternIndex < CatHeader.nPatterns) : (PatternIndex += 1)
            {
                try Self.CatIDs.append(@intCast(c_uint, CatIndex));
            }

            // Read module's source code
            var SourceZ = try Self.Ally.alloc(u8, CatHeader.nPySourceBytes + 1);
            defer Self.Ally.free(SourceZ); // We don't need to keep this around.
            debug.assert(try ArtiF.readAll(SourceZ[0 .. CatHeader.nPySourceBytes]) ==
                CatHeader.nPySourceBytes);
            SourceZ[SourceZ.len - 1] = 0;

            try sempy.LoadModuleFromSource(LMod.NameZ, SourceZ);
            try Self.LoadedPyModules.append(LMod);
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

export fn GracieExtract(Ctx: ?*?*anyopaque, Text: ?[*]const u8,
    nTextBytes: c_uint) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    Extract(Self.?.*.?, Text.?[0 .. nTextBytes]) catch |Err|
        return ErrToCode(Err);
    return GRACIE_SUCCESS;
}

pub fn Extract(Self: *self, Text: []const u8) !void
{
    // Reset stuff
    Self.MatchList.clearRetainingCapacity();

    // Hyperscannnnn!!
    try HSCodeToErr(c.hs_scan(Self.Database, Text.ptr, @intCast(c_uint, Text.len), 0, Self.Scratch,
            EventHandler, Self));
    for (Self.MatchList.items) |M|
    {
        //FIXME(cjb): LoadedPyModules[0]
        try sempy.RunModule(Text[M.SO .. M.EO], Self.LoadedPyModules.items[0].NameZ);
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
    Self.Ally.free(@ptrCast([*]u8, Self.Database.?)[0 .. Self.nDatabaseBytes]);

    for (Self.LoadedPyModules.items) |Mod|
    {
        Self.Ally.free(Mod.NameZ);
    }
    Self.LoadedPyModules.deinit();
    Self.MatchList.deinit();
    Self.CatIDs.deinit();

    // Deinitialize sempy
    try sempy.Deinit();
}

test "Gracie"
{
    var Ally = std.testing.allocator;
    var G = try self.Init(Ally, "./data/gracie.bin");
    try self.Extract(&G, "Earn $300 an hour"[0 ..]);
    try self.Deinit(&G);
}
