const std = @import("std");
const array_list = std.ArrayList;
const slab_allocator = @import("slab_allocator.zig");

const c = @cImport({
    @cInclude("hs.h");
    @cInclude("sempy.h");
});

pub const gracie_artifact_header = extern struct
{
    DatabaseSize: usize,
    nPatterns: usize,
};

const gracie = struct
{
    Database: ?*c.hs_database_t,
    Scratch: ?*c.hs_scratch_t,
    Slaba: slab_allocator,
    BackingBuffer: []u8,

    /// Arr of category ids, where pattern id is the index of the associated category id.
    CategoryIDs: ?[*]c_uint,
    MatchList: array_list(gracie_match),
};

const gracie_match = struct
{
    SO: c_ulonglong,
    EO: c_ulonglong,
    CategoryID: c_uint,
};

pub const GRACIE_SUCCESS: c_int = 0;        // Call was executed successfully
pub const GRACIE_INVALID: c_int = -1;       // Bad paramater was passed
pub const GRACIE_UNKNOWN_ERROR: c_int = -2; // Unhandled internal error
pub const GRACIE_NOMEM: c_int = -3;         // A memory allocation failed

// TODO(cjb): Integrate this error set into GracieErrhandler.
fn HSLogErrOnFail(HSReturnCode: c_int) !void {
    switch (HSReturnCode) {
        c.HS_SUCCESS => return,
        c.HS_INVALID => std.log.err("HS_INVALID\n", .{}),
        c.HS_NOMEM => std.log.err("HS_NOMEM\n", .{}),
        c.HS_SCAN_TERMINATED => std.log.err("HS_SCAN_TERMINATED\n", .{}),
        c.HS_COMPILER_ERROR => std.log.err("HS_COMPILER_ERROR\n", .{}),
        c.HS_DB_VERSION_ERROR => std.log.err("HS_DB_VERSION_ERROR\n", .{}),
        c.HS_DB_PLATFORM_ERROR => std.log.err("HS_DB_PLATFORM_ERROR\n", .{}),
        c.HS_DB_MODE_ERROR => std.log.err("HS_DB_MODE_ERROR\n", .{}),
        c.HS_BAD_ALIGN => std.log.err("HS_BAD_ALIGN\n", .{}),
        c.HS_BAD_ALLOC => std.log.err("HS_BAD_ALLOC\n", .{}),
        c.HS_SCRATCH_IN_USE => std.log.err("HS_SCRATCH_IN_USE\n", .{}),
        c.HS_ARCH_ERROR => std.log.err("HS_ARCH_ERROR\n", .{}),
        c.HS_INSUFFICIENT_SPACE => std.log.err("HS_INSUFFICIENT_SPACE\n", .{}),
        c.HS_UNKNOWN_ERROR => std.log.err("HS_UNKNOWN_ERROR\n", .{}),
        else => unreachable,
    }
    return error.Error;
}

fn GracieErrHandler(Err: anyerror) c_int
{
    std.log.err("{}", .{Err});
    switch(Err)
    {
        error.OutOfMemory => return GRACIE_NOMEM,
        error.FileNotFound => return GRACIE_INVALID,
        error.Error => return GRACIE_UNKNOWN_ERROR,
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

export fn GracieInit(Gracie: ?*?*gracie, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    // Open artifact file
    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }
    const ArtifactFile = std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{}) catch |Err|
        return GracieErrHandler(Err);

    // Read artifact header
    var ArtifactHeader: gracie_artifact_header = undefined;
    const nHeaderBytesRead = ArtifactFile.read(
        @ptrCast([*]u8, &ArtifactHeader)[0..@sizeOf(gracie_artifact_header)]) catch |Err|
        return GracieErrHandler(Err);
    std.debug.assert(nHeaderBytesRead == @sizeOf(gracie_artifact_header));

    // Setup slab allocator TODO(cjb): Make slab allocator alloc pages
    var BackingBuffer = std.heap.page_allocator.alloc(u8,
        ArtifactHeader.DatabaseSize*3 // Need to store serialized buffer and
                                      // database at same time
        + 0x1000*4) catch |Err| return GracieErrHandler(Err);
    var Slaba = slab_allocator.Init(BackingBuffer);
    var Ally = slab_allocator.Allocator(&Slaba);

     // Allocate new gracie context and copy alloactor over to it
    Gracie.?.*.? = Ally.create(gracie) catch |Err|
        return GracieErrHandler(Err);
    Gracie.?.*.?.Slaba = Slaba;
    Gracie.?.*.?.BackingBuffer = BackingBuffer;
    Ally = slab_allocator.Allocator(&Gracie.?.*.?.Slaba); // Allocator at this slaba

    // Read serialized database
    var SerializedBytes = Ally.alloc(u8, ArtifactHeader.DatabaseSize) catch |Err|
        return GracieErrHandler(Err);
    defer Ally.free(SerializedBytes);

    const nDatabaseBytesRead = ArtifactFile.reader().readAll(SerializedBytes) catch |Err|
        return GracieErrHandler(Err);
    std.debug.assert(nDatabaseBytesRead == ArtifactHeader.DatabaseSize);

    //var HSAlloc: c.hs_alloc_t = Bannans;
    //var HSFree: c.hs_free_t = Bannans2;
    // typedef void *(*hs_alloc_t)(size_t size)
    // typedef void (*hs_free_t)(void *ptr)
    // hs_error_t hs_set_allocator(hs_alloc_t alloc_func, hs_free_t free_func)

    // TODO(cjb): hs_set_misc_allocator()
    var DatabaseBuf = Ally.alloc(u8, ArtifactHeader.DatabaseSize) catch |Err|
        return GracieErrHandler(Err);
    Gracie.?.*.?.Database = @ptrCast(*c.hs_database_t,
        @alignCast(@alignOf(c.hs_database_t), DatabaseBuf.ptr));

    HSLogErrOnFail(c.hs_deserialize_database_at(
            SerializedBytes.ptr, SerializedBytes.len,
            Gracie.?.*.?.Database)) catch |Err|
        return GracieErrHandler(Err);

    // TODO(cjb): set allocator used for scratch
    Gracie.?.*.?.Scratch = null;
    HSLogErrOnFail(c.hs_alloc_scratch(Gracie.?.*.?.Database, &Gracie.?.*.?.Scratch)) catch |Err|
        return GracieErrHandler(Err);

    // Initialize category ids
    var CategoryIDs = Ally.alloc(c_uint, ArtifactHeader.nPatterns) catch |Err|
        return GracieErrHandler(Err);

    // Read pattern id & category id
    var PatCatIndex: usize = 0;
    while (PatCatIndex < ArtifactHeader.nPatterns) : (PatCatIndex += 1)
    {
        var IDBuf = ArtifactFile.reader().readBytesNoEof(4) catch |Err|
            return GracieErrHandler(Err);
        const IDPtr = @ptrCast(*c_uint, @alignCast(@alignOf(c_uint), &IDBuf));
        var CatBuf = ArtifactFile.reader().readBytesNoEof(4) catch |Err|
            return GracieErrHandler(Err);
        const Cat = @ptrCast(*c_uint, @alignCast(@alignOf(c_uint), &CatBuf));
        CategoryIDs[IDPtr.*] = Cat.*;
    }
    Gracie.?.*.?.CategoryIDs = @ptrCast(?[*]c_uint, CategoryIDs.ptr);

    // Initialize match array list
    Gracie.?.*.?.MatchList = array_list(gracie_match).init(Ally);

    // Initialize python plugins
    _ = c.SempyInit();

    const DEBUGSource =
        \\def foo(Text: str, CategoryID: int) -> None:
        \\  print(f'{Text} + {CategoryID}')
    ;
    _ = c.SempyLoadModuleFromSource(DEBUGSource, DEBUGSource.len);

    return GRACIE_SUCCESS;
}

fn EventHandler(ID: c_uint, From: c_ulonglong, To: c_ulonglong, _: c_uint,
    Ctx: ?*anyopaque) callconv(.C) c_int
{
    const GraciePtr = @ptrCast(?*gracie, @alignCast(@alignOf(?*gracie), Ctx));
    if (GraciePtr.?.MatchList.items.len + 1 > GraciePtr.?.MatchList.capacity)
    {
        GraciePtr.?.MatchList.append(.{.SO=From, .EO=To,
            .CategoryID=GraciePtr.?.CategoryIDs.?[ID]}) catch unreachable;
        return 0;
    }
    return 1;
}

export fn GracieExtract(Gracie: ?*?*gracie, Text: ?[*]u8, nTextBytes: c_uint) callconv(.C) c_int
{
    const GraciePtr = Gracie.?.*.?;

    // Reset stuff
    GraciePtr.MatchList.clearRetainingCapacity();

    HSLogErrOnFail(c.hs_scan(GraciePtr.Database, Text, nTextBytes, 0,
            GraciePtr.Scratch, EventHandler, GraciePtr)) catch |Err|
        return GracieErrHandler(Err);

    for (GraciePtr.MatchList.items) |M|
    {
        const TextSOPtr = @intToPtr(?[*]const u8, @ptrToInt(Text) + @intCast(usize, M.SO));
        _ = c.SempyRunModule(TextSOPtr, @intCast(usize, M.EO - M.SO), M.CategoryID);
    }

    slab_allocator.DEBUGSlabVisularizer(&GraciePtr.Slaba);

    return GRACIE_SUCCESS;
}

export fn GracieDeinit(Gracie: ?*?*gracie) callconv(.C) c_int {
    _ = c.hs_free_scratch(Gracie.?.*.?.Scratch);
    _ = c.SempyDeinit();

    std.heap.page_allocator.free(Gracie.?.*.?.BackingBuffer);

    return GRACIE_SUCCESS;
}

test "init then deinit"
{
    var GracieCtx: ?*gracie = null;
    try std.testing.expect(
        GracieInit(&GracieCtx, "./data/gracie.bin") ==
        GRACIE_SUCCESS);
    try std.testing.expect(
        GracieDeinit(&GracieCtx) ==
        GRACIE_SUCCESS);
}
