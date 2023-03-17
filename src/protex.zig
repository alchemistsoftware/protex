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

const op_pymodule = common.op_pymodule;
const op_capture = common.op_capture;
const op_type = common.op_type;

pub const op = union(op_type)
{
    PyModule: op_pymodule,
    Capture: op_capture,
};

const match = struct
{
    SO: c_ulonglong,
    EO: c_ulonglong,
    ID: c_uint,
};

const extractor_def = struct
{
    Name: []u8,
    OpQs: [][]op,
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
pub const PROTEX_SUCCESS: c_int = 0;

/// Bad paramater was passed
pub const PROTEX_INVALID: c_int = -1;

/// Unhandled internal error
pub const PROTEX_UNKNOWN_ERROR: c_int = -2;

/// A memory allocation failed
pub const PROTEX_NOMEM: c_int = -3;

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

/// Map zig errors to status code.
fn ErrToCode(Err: anyerror) c_int
{
    std.log.err("{}", .{Err});
    switch(Err)
    {
        error.OutOfMemory => return PROTEX_NOMEM,
        error.FileNotFound,
        error.BadConditonStatment => return PROTEX_INVALID,
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
        error.SempyUnknown => return PROTEX_UNKNOWN_ERROR,

        else => unreachable,
    }
}

export fn ProtexInit(Ctx: ?*?*anyopaque, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    var Ally = std.heap.page_allocator;
    Self.?.* = Ally.create(self) catch |Err|
        return ErrToCode(Err);

    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }

    Self.?.*.?.* = Init(Ally, ArtifactPathZ.?[0 .. PathLen]) catch |Err|
        return ErrToCode(Err);
    return PROTEX_SUCCESS;
}

pub fn Init(Ally: allocator, ArtifactPath: []const u8) !self
{
    var Self: self = undefined;
    Self.Ally = Ally;

    // Open artifact file and obtain header in order to begin parsing.

    const ArtiF = try std.fs.cwd().openFile(ArtifactPath, .{});
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
    // TODO(cjb): set allocator used for scratch

    Self.Scratch = null; // HS is weird about scratch being null
    Self.ExtrDefs = try Self.Ally.alloc(extractor_def, ArtiHeader.nExtractorDefs);

    var ExtractorDefIndex: usize = 0;
    while (ExtractorDefIndex < ArtiHeader.nExtractorDefs) : (ExtractorDefIndex += 1)
    {
        const DefHeader = try R.readStruct(common.arti_def_header);
        var ExtrDef: extractor_def = undefined;

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

        try HSCodeToErr(c.hs_alloc_scratch(ExtrDef.Database, &Self.Scratch));

//
// Read operation data
//

        ExtrDef.OpQs = try Self.Ally.alloc([]op, DefHeader.nOperationQueues);
        var OpQIndex: usize = 0;
        while (OpQIndex < DefHeader.nOperationQueues) : (OpQIndex += 1)
        {
            const OpQHeader = try R.readStruct(common.arti_op_q_header);
            ExtrDef.OpQs[OpQIndex] = try Self.Ally.alloc(op, OpQHeader.nOps);
            var OpIndex: usize = 0;
            while (OpIndex < OpQHeader.nOps) : (OpIndex += 1)
            {
                const OpType = @intToEnum(op_type,
                    try R.readInt(@typeInfo(op_type).Enum.tag_type, std.builtin.Endian.Little));

                var Op: op = undefined;
                switch(OpType)
                {
                    op_type.PyModule =>
                    {
                        Op = op{.PyModule = try R.readStruct(op_pymodule),};
                    },
                    op_type.Capture =>
                    {
                        Op = op{.Capture = try R.readStruct(op_capture),};
                    },
                }

                ExtrDef.OpQs[OpQIndex][OpIndex] = Op;
            }
        }

        Self.ExtrDefs[ExtractorDefIndex] = ExtrDef;
    }

    // Initialize extractor scratch buffer

    Self.FBackBuf = try Ally.alloc(u8, 1024*1024);

    return Self;
}

fn HSMatchHandler(ID: c_uint, From: c_ulonglong, To: c_ulonglong, _: c_uint,
    Ctx: ?*anyopaque) callconv(.C) c_int
{
    const MatchList = @ptrCast(?*array_list(match),
        @alignCast(@alignOf(?*array_list(match)), Ctx)) orelse unreachable;

    // TODO(cjb): Decide if this should be handled or not. (just make this fixed size)

    MatchList.append(.{.SO=From, .EO=To, .ID=ID}) catch unreachable;
    return 0;
}

export fn ProtexExtract(Ctx: ?*?*anyopaque, Text: ?[*]const u8,
    nTextBytes: c_uint, Result: ?*[*]u8, nBytesCopied: ?*c_uint) callconv(.C) c_int
{
    var Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    var ExtractResult = Extract(Self.?.*.?, Text.?[0 .. nTextBytes]) catch |Err|
        return ErrToCode(Err);

    nBytesCopied.?.* = @intCast(c_uint, ExtractResult.len);
    Result.?.* = @ptrCast([*]u8, ExtractResult.ptr);
    return PROTEX_SUCCESS;
}

pub fn Extract(Self: *self, Text: []const u8) ![]u8
{
    var FBAlly = fixed_buffer_allocator.init(Self.FBackBuf);

    // Store HYPERSCAN matches somewhere.

    var MatchList = array_list(match).init(FBAlly.allocator());

    // Buffers for stream & sempy output.

    var SempyRunBuf = try FBAlly.allocator().alloc(u8, 1024*1);
    var ReturnBuf = try FBAlly.allocator().alloc(u8, 1024*10);

    var JSONStream = std.io.fixedBufferStream(ReturnBuf);
    var W = std.json.writeStream(JSONStream.writer(), 5);

    try W.beginObject();
    for (Self.ExtrDefs) |ExtractorDef|
    {
        // Scan this extractor's HYPERSCAN database.

        MatchList.clearRetainingCapacity();
        try HSCodeToErr(c.hs_scan(ExtractorDef.Database, Text.ptr,
                @intCast(c_uint, Text.len), 0, Self.Scratch, HSMatchHandler, &MatchList));

        const nTextMatches = MatchList.items.len;

        // Begin JSON array labeled with this extractor's name containing categories.

        try W.objectField(ExtractorDef.Name);
        try W.beginArray();

        //TODO(cjb): Decide how to handle multi matches within same category

        for (ExtractorDef.OpQs) |OpQ|
        {
            try W.arrayElem();
            try W.beginObject();

            var LatestPyModuleMatchCount: usize = 0;
            var LatestMatch: match = undefined;
            var LatestExtractTarget = Text;

            for (OpQ) |Op, OpIndex|
            {
                switch(Op)
                {
                    op_type.PyModule =>
                    {
                        // Pass entire text if this is first op

                        const GarbageID = 123;
                        if (OpIndex == 0)
                        {
                            LatestMatch = match{.SO=0, .EO=LatestExtractTarget.len, .ID=GarbageID};
                        }

                        const nBytesCopied = try sempy.Run(
                            Self.PyCallbacks.items[@intCast(usize, Op.PyModule.Index)],
                            LatestExtractTarget,
                            LatestMatch.SO,
                            LatestMatch.EO,
                            SempyRunBuf);

                        LatestExtractTarget = SempyRunBuf[0..nBytesCopied];
                        LatestMatch = match{.SO=0, .EO=LatestExtractTarget.len, .ID=GarbageID};

                        var MatchListIndex: usize = 0;
                        while (MatchListIndex < LatestPyModuleMatchCount) : (MatchListIndex += 1)
                        {
                            _ = MatchList.pop();
                        }

                        try HSCodeToErr(c.hs_scan(ExtractorDef.Database, LatestExtractTarget.ptr,
                            @intCast(c_uint, LatestExtractTarget.len), 0, Self.Scratch,
                            HSMatchHandler, &MatchList));

                        LatestPyModuleMatchCount = MatchList.items.len - nTextMatches;
                    },
                    op_type.Capture =>
                    {
                        var MatchView: []match = undefined;
                        if (LatestExtractTarget.ptr == Text.ptr)
                        {
                            MatchView = MatchList.items[0 .. nTextMatches];
                        }
                        else
                        {
                           MatchView = MatchList.items
                               [nTextMatches .. nTextMatches + LatestPyModuleMatchCount];
                        }

                        for (MatchView) |Match|
                        {
                            if (@intCast(c_uint, Op.Capture.PatternID) == Match.ID)
                            {
                                LatestMatch = Match;
                                LatestMatch.EO = @min(LatestMatch.EO + Op.Capture.Offset,
                                                        LatestExtractTarget.len);
                                break;
                            }
                        }
                    },
                }
            }

            try W.objectField("Out");
            try W.emitString(LatestExtractTarget[LatestMatch.SO..LatestMatch.EO]);

            // Spit out match indicies ( For config client's benifit )

            try W.objectField("SO");
            try W.emitNumber(LatestMatch.SO);
            try W.objectField("EO");
            try W.emitNumber(LatestMatch.EO);

            try W.endObject(); // End this operation queue's JSON blurb.
        }
        try W.endArray(); // End extractor's list of JSON blurbs.
    }
    try W.endObject(); // End root JSON object.

    return JSONStream.getWritten(); // Return JSON which was just written.
}

export fn ProtexDeinit(Ctx: ?*?*anyopaque) callconv(.C) c_int
{
    const Self = @ptrCast(?*?*self, @alignCast(@alignOf(?*self), Ctx));
    Deinit(Self.?.*.?);
    Self.?.*.?.Ally.destroy(Self.?.*.?);
    return PROTEX_SUCCESS;
}

pub fn Deinit(Self: *self) void
{
    HSCodeToErr(c.hs_free_scratch(Self.Scratch)) catch unreachable;

    Self.Ally.free(Self.FBackBuf);

    for (Self.ExtrDefs) |Def|
    {
        Self.Ally.free(Def.Name);
        for (Def.OpQs) |OpQ|
        {
								    Self.Ally.free(OpQ);
        }
        Self.Ally.free(Def.OpQs);
        Self.Ally.free(@ptrCast([*]u8, Def.Database.?)[0 .. Def.nDatabaseBytes]);
    }
    Self.Ally.free(Self.ExtrDefs);

    // TODO(cjb): Have sempy own PyCallbacks array list
    for (Self.PyCallbacks.items) |CB| sempy.UnloadCallbackFn(CB);
    Self.PyCallbacks.deinit();

    // Deinitialize sempy
    sempy.Deinit();
}

test "Protex C"
{
    var G: ?*anyopaque = undefined;
    var Result: [*]u8 = undefined;
    var nBytesCopied: c_uint = undefined;
    const Text = "Earn $30 an hour";

    debug.assert(ProtexInit(&G, "./data/protex.bin") == PROTEX_SUCCESS);
    debug.assert(ProtexExtract(&G, Text, Text.len, &Result, &nBytesCopied) == PROTEX_SUCCESS);
    debug.assert(ProtexDeinit(&G) == PROTEX_SUCCESS);
}

test "Protex"
{
    var Ally = std.testing.allocator;
    var G = try self.Init(Ally, "./data/protex.bin");
    _ = try self.Extract(&G, "Earn $30 an hour");
    self.Deinit(&G);
}
