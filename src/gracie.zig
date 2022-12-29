const std = @import("std");
const slab_allocator = @import("slab_allocator.zig");
const common = @import("common.zig");
const sempy = @import("sempy.zig");
const c = @cImport({
    @cInclude("hs.h");
});

const array_list = std.ArrayList;
const assert = std.debug.assert;
const gracie_artifact_header = common.gracie_arti_header;

const self = @This();

const gracie_match = struct
{
    SO: c_ulonglong,
    EO: c_ulonglong,
    CategoryID: c_uint,
};

Database: ?*c.hs_database_t,
Scratch: ?*c.hs_scratch_t,
SlabAlly: slab_allocator,
BackingBuffer: []u8,

/// Arr of category ids, where pattern id is the index of the associated category id.
CategoryIDs: ?[*]c_uint,
MatchList: array_list(gracie_match),

pub const GRACIE_SUCCESS: c_int = 0;        // Call was executed successfully
pub const GRACIE_INVALID: c_int = -1;       // Bad paramater was passed
pub const GRACIE_UNKNOWN_ERROR: c_int = -2; // Unhandled internal error
pub const GRACIE_NOMEM: c_int = -3;         // A memory allocation failed

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

// HACK(cjb): Fine? ( on the upside could ommit throwing ?*?*gracie ptrs all over )
//  Introduced to set hs_allocator
//var GracieCtx: ?*gracie = undefined;
//fn Bannans(Size: usize) ?*anyopaque
//{
//    var Ptr = GracieAAlloc(&GracieCtx.?.SlabAlly, Size);
//    return Ptr;
//}
export fn GracieInit(Ctx: ?*?*anyopaque, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    return Init(Ctx, ArtifactPathZ);
}


// TODO(cjb): Attempt to register an errdefer so try becomes avial?
pub fn Init(Ctx: ?*?*anyopaque, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));

//
// Allocator setup
//
    // Setup slab allocator TODO(cjb): Make slab allocator alloc pages
    var BackingBuffer = std.heap.page_allocator.alloc(u8, 0x1000*8) catch |Err|
        return ErrToCode(Err);
    var SlabAlly = slab_allocator.Init(BackingBuffer);

    // Tmp allocator
    var Ally = slab_allocator.Allocator(&SlabAlly);

    // Allocate new gracie context and copy alloactor over to it
    Self.?.*.? = Ally.create(self) catch |Err|
        return ErrToCode(Err);
    Self.?.*.?.SlabAlly = SlabAlly;
    Self.?.*.?.BackingBuffer = BackingBuffer;

    // Change to slab allocator now owned by this ctx
    Ally = slab_allocator.Allocator(&Self.?.*.?.SlabAlly);

//
// Deserialize artifact
//
    // Open artifact file
    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }
    const ArtiF = std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{}) catch |Err|
        return ErrToCode(Err);

    // Read artifact header
    const ArtiHeader = ArtiF.reader().readStruct(common.gracie_artifact_header) catch |Err|
        return ErrToCode(Err);

    // Read n extractor definitions
    var ExtractorDefIndex: usize = 0;
    while (ExtractorDefIndex < ArtiHeader.nExtractorDefs) : (ExtractorDefIndex += 1)
    {
        // Read definition header
        const ExtractorDefHeader = ArtiF.reader()
            .readStruct(common.gracie_extractor_def_header) catch |Err|
                return ErrToCode(Err);

        ArtiF.reader().skipBytes(2 + 2 + ExtractorDefHeader.nExtractorNameBytes, {}) catch |Err|
            return ErrToCode(Err);

    //    var Country: [2]u8 = undefined;
    //    _ = ArtiF.reader().readAll(Country) catch |Err|
    //        return ErrToCode(Err);

    //    var Language: [2]u8 = undefined;
    //    _ = ArtiF.reader().readAll(Language) catch |Err|
    //        return ErrToCode;

        // Read serialized database
        var SerializedBytes = Ally.alloc(u8, ExtractorDefHeader.DatabaseSize) catch |Err|
            return ErrToCode(Err);
        defer Ally.free(SerializedBytes);

        const nDatabaseBytesRead = ArtiF.reader().readAll(SerializedBytes) catch |Err|
            return ErrToCode(Err);

        //var HSAlloc: c.hs_alloc_t = Bannans;
        //var HSFree: c.hs_free_t = Bannans2;
        // typedef void *(*hs_alloc_t)(size_t size)
        // typedef void (*hs_free_t)(void *ptr)
        // hs_error_t hs_set_allocator(hs_alloc_t alloc_func, hs_free_t free_func)

        // TODO(cjb): hs_set_misc_allocator()
        var DatabaseBuf = Ally.alloc(u8, ExtractorDefHeader.DatabaseSize) catch |Err|
            return ErrToCode(Err);
        Self.?.*.?.Database = @ptrCast(*c.hs_database_t,
            @alignCast(@alignOf(c.hs_database_t), DatabaseBuf.ptr));

        HSCodeToErr(c.hs_deserialize_database_at(
                SerializedBytes.ptr, SerializedBytes.len,
                Self.?.*.?.Database)) catch |Err|
            return ErrToCode(Err);

        // TODO(cjb): set allocator used for scratch
        Self.?.*.?.Scratch = null;
        HSCodeToErr(c.hs_alloc_scratch(Self.?.*.?.Database, &Self.?.*.?.Scratch)) catch |Err|
            return ErrToCode(Err);

        // TODO(cjb): left off here...

        // Initialize category ids
        var CategoryIDs = Ally.alloc(c_uint, 1024) catch |Err| //ArtifactHeader.nPatterns) catch |Err|
            return ErrToCode(Err);

        // Read pattern id & category id
        var PatCatIndex: usize = 0;
        while (PatCatIndex < ExtractorDefHeader.nPatterns) : (PatCatIndex += 1)
        {
            var IDBuf = ArtiF.reader().readBytesNoEof(4) catch |Err|
                return ErrToCode(Err);
            const IDPtr = @ptrCast(*c_uint, @alignCast(@alignOf(c_uint), &IDBuf));
            var CatBuf = ArtiF.reader().readBytesNoEof(4) catch |Err|
                return ErrToCode(Err);
            const Cat = @ptrCast(*c_uint, @alignCast(@alignOf(c_uint), &CatBuf));
            CategoryIDs[IDPtr.*] = Cat.*;
        }
        Self.?.*.?.CategoryIDs = @ptrCast(?[*]c_uint, CategoryIDs.ptr);

        // Initialize match array list
        Self.?.*.?.MatchList = array_list(gracie_match).init(Ally);

        // Initialize python plugins
        sempy.Init() catch |Err|
            return ErrToCode(Err);

        // TODO(cjb): Load plugin code from packager bytes
        var DEBUGSource =
        \\def SempyMain(Text: str, CategoryID: int) -> None:
        \\    Num: int = 0
        \\    for W in Text.split(' '):
        \\        if (W[0] == '$'):
        \\          Num = int(W[1:])
        \\          break
        \\    if (CategoryID == 0): # Dealing with hourly salary
        \\        Num *= 8 * 5 * 4 * 12
        \\    print(f'Salary: {Num}')
        ;
        var SMCtx = sempy.module_ctx{.Source=DEBUGSource, .Name="us_en_salary"};
        sempy.LoadModuleFromSource(&SMCtx) catch |Err|
            return ErrToCode(Err);
    }

    return GRACIE_SUCCESS;
}

fn EventHandler(ID: c_uint, From: c_ulonglong, To: c_ulonglong, _: c_uint,
    Ctx: ?*anyopaque) callconv(.C) c_int
{
    const GraciePtr = @ptrCast(?*self, @alignCast(@alignOf(?*self), Ctx));
    if (GraciePtr.?.MatchList.items.len + 1 > GraciePtr.?.MatchList.capacity)
    {
        GraciePtr.?.MatchList.append(.{.SO=From, .EO=To,
            .CategoryID=GraciePtr.?.CategoryIDs.?[ID]}) catch unreachable;
        return 0;
    }
    return 1;
}

export fn GracieExtract(Ctx: ?*?*anyopaque, Text: ?[*]u8, nTextBytes: c_uint) callconv(.C) c_int
{
    return Extract(Ctx, Text, nTextBytes);
}

pub fn Extract(Ctx: ?*?*anyopaque, Text: ?[*]u8, nTextBytes: c_uint) callconv(.C) c_int
{
    const Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    const GraciePtr = Self.?.*.?;

    // Reset stuff
    GraciePtr.MatchList.clearRetainingCapacity();

    // HYPERSCANNNNN!!
    HSCodeToErr(c.hs_scan(GraciePtr.Database, Text, nTextBytes, 0,
            GraciePtr.Scratch, EventHandler, GraciePtr)) catch |Err|
        return ErrToCode(Err);

    //slab_allocator.DEBUGSlabVisularizer(&GraciePtr.SlabAlly);
    for (GraciePtr.MatchList.items) |M|
    {
        sempy.RunModule(Text.?[M.SO .. M.EO], M.CategoryID) catch |Err|
            return ErrToCode(Err);
    }
    return GRACIE_SUCCESS;
}

export fn GracieDeinit(Ctx: ?*?*anyopaque) callconv(.C) c_int
{
    return Deinit(Ctx);
}

pub fn Deinit(Ctx: ?*?*anyopaque) callconv(.C) c_int
{
    const Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    const SelfPtr = Self.?.*.?;

    // Free hs scratch
    HSCodeToErr(c.hs_free_scratch(SelfPtr.Scratch)) catch |Err|
        return ErrToCode(Err);

    // Deinitialize sempy
    sempy.Deinit() catch |Err|
        return ErrToCode(Err);

    // Free backing buffer
    std.heap.page_allocator.free(SelfPtr.BackingBuffer);

    // Invalidate ptr
    Self.?.* = null;

    return GRACIE_SUCCESS;
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
