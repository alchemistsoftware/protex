const std = @import("std");
const array_list = std.ArrayList;
const slab_allocator = @import("slab_allocator.zig");
const common = @import("common.zig");
const sempy = @import("sempy.zig");
const c = @cImport({
    @cInclude("hs.h");
});

const gracie_artifact_header = common.gracie_artifact_header;

const self = @This();

const gracie_match = struct
{
    SO: c_ulonglong,
    EO: c_ulonglong,
    CategoryID: c_uint,
};

Database: ?*c.hs_database_t,
Scratch: ?*c.hs_scratch_t,
Slaba: slab_allocator,
BackingBuffer: []u8,

/// Arr of category ids, where pattern id is the index of the associated category id.
CategoryIDs: ?[*]c_uint,
MatchList: array_list(gracie_match),

pub const GRACIE_SUCCESS: c_int = 0;        // Call was executed successfully
pub const GRACIE_INVALID: c_int = -1;       // Bad paramater was passed
pub const GRACIE_UNKNOWN_ERROR: c_int = -2; // Unhandled internal error
pub const GRACIE_NOMEM: c_int = -3;         // A memory allocation failed

fn HSStatusToErr(ReturnCode: c_int) !void
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

fn ErrHandler(Err: anyerror) c_int
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
//    var Ptr = GracieAAlloc(&GracieCtx.?.Slaba, Size);
//    return Ptr;
//}
export fn GracieInit(Ctx: ?*?*anyopaque, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    return Init(Ctx, ArtifactPathZ);
}

pub fn Init(Ctx: ?*?*anyopaque, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));

    // Open artifact file
    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }
    const ArtifactFile = std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{}) catch |Err|
        return ErrHandler(Err);

    // Read artifact header
    var ArtifactHeader: gracie_artifact_header = undefined;
    const nHeaderBytesRead = ArtifactFile.read(
        @ptrCast([*]u8, &ArtifactHeader)[0..@sizeOf(gracie_artifact_header)]) catch |Err|
        return ErrHandler(Err);
    std.debug.assert(nHeaderBytesRead == @sizeOf(gracie_artifact_header));

    // Setup slab allocator TODO(cjb): Make slab allocator alloc pages
    var BackingBuffer = std.heap.page_allocator.alloc(u8,
        1024*3//ArtifactHeader.DatabaseSize*3 // Need to store serialized buffer and
                                      // database at same time
        + 0x1000*4) catch |Err| return ErrHandler(Err);
    var Slaba = slab_allocator.Init(BackingBuffer);
    var Ally = slab_allocator.Allocator(&Slaba);

     // Allocate new gracie context and copy alloactor over to it
    Self.?.*.? = Ally.create(self) catch |Err|
        return ErrHandler(Err);
    Self.?.*.?.Slaba = Slaba;
    Self.?.*.?.BackingBuffer = BackingBuffer;
    Ally = slab_allocator.Allocator(&Self.?.*.?.Slaba); // Allocator at this slaba

    // Read serialized database
    var SerializedBytes = Ally.alloc(u8, 1024) catch |Err|//ArtifactHeader.DatabaseSize) catch |Err|
        return ErrHandler(Err);
    defer Ally.free(SerializedBytes);

    const nDatabaseBytesRead = ArtifactFile.reader().readAll(SerializedBytes) catch |Err|
        return ErrHandler(Err);
    std.debug.assert(nDatabaseBytesRead == 1024);//ArtifactHeader.DatabaseSize);

    //var HSAlloc: c.hs_alloc_t = Bannans;
    //var HSFree: c.hs_free_t = Bannans2;
    // typedef void *(*hs_alloc_t)(size_t size)
    // typedef void (*hs_free_t)(void *ptr)
    // hs_error_t hs_set_allocator(hs_alloc_t alloc_func, hs_free_t free_func)

    // TODO(cjb): hs_set_misc_allocator()
    var DatabaseBuf = Ally.alloc(u8, 1024) catch |Err| //ArtifactHeader.DatabaseSize) catch |Err|
        return ErrHandler(Err);
    Self.?.*.?.Database = @ptrCast(*c.hs_database_t,
        @alignCast(@alignOf(c.hs_database_t), DatabaseBuf.ptr));

    HSStatusToErr(c.hs_deserialize_database_at(
            SerializedBytes.ptr, SerializedBytes.len,
            Self.?.*.?.Database)) catch |Err|
        return ErrHandler(Err);

    // TODO(cjb): set allocator used for scratch
    Self.?.*.?.Scratch = null;
    HSStatusToErr(c.hs_alloc_scratch(Self.?.*.?.Database, &Self.?.*.?.Scratch)) catch |Err|
        return ErrHandler(Err);

    // Initialize category ids
    var CategoryIDs = Ally.alloc(c_uint, 1024) catch |Err| //ArtifactHeader.nPatterns) catch |Err|
        return ErrHandler(Err);

    // Read pattern id & category id
    var PatCatIndex: usize = 0;
    while (PatCatIndex < 1024) : (PatCatIndex += 1)//ArtifactHeader.nPatterns) : (PatCatIndex += 1)
    {
        var IDBuf = ArtifactFile.reader().readBytesNoEof(4) catch |Err|
            return ErrHandler(Err);
        const IDPtr = @ptrCast(*c_uint, @alignCast(@alignOf(c_uint), &IDBuf));
        var CatBuf = ArtifactFile.reader().readBytesNoEof(4) catch |Err|
            return ErrHandler(Err);
        const Cat = @ptrCast(*c_uint, @alignCast(@alignOf(c_uint), &CatBuf));
        CategoryIDs[IDPtr.*] = Cat.*;
    }
    Self.?.*.?.CategoryIDs = @ptrCast(?[*]c_uint, CategoryIDs.ptr);

    // Initialize match array list
    Self.?.*.?.MatchList = array_list(gracie_match).init(Ally);

    // Initialize python plugins
    sempy.Init() catch |Err|
        return ErrHandler(Err);

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
        return ErrHandler(Err);

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

    //TODO(cjb):

    // Reset stuff
    GraciePtr.MatchList.clearRetainingCapacity();

    // HYPERSCANNNNN!!
    HSStatusToErr(c.hs_scan(GraciePtr.Database, Text, nTextBytes, 0,
            GraciePtr.Scratch, EventHandler, GraciePtr)) catch |Err|
        return ErrHandler(Err);

    //slab_allocator.DEBUGSlabVisularizer(&GraciePtr.Slaba);
    for (GraciePtr.MatchList.items) |M|
    {
        sempy.RunModule(Text.?[M.SO .. M.EO], M.CategoryID) catch |Err|
            return ErrHandler(Err);
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
    HSStatusToErr(c.hs_free_scratch(SelfPtr.Scratch)) catch |Err|
        return ErrHandler(Err);

    // Deinitialize sempy
    sempy.Deinit() catch |Err|
        return ErrHandler(Err);

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
