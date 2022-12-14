const std = @import("std");
const gracie = @import("gracie.zig");

const c = @cImport({
    @cInclude("hs.h");
});

pub fn main() !void {
    // Allocate a scratch and patterns buffer.
    var ScratchBuffer: [1024]u8 = undefined;
    var PatternsBuffer: [1024]u8 = undefined;
    var ScratchFBA = std.heap.FixedBufferAllocator.init(&ScratchBuffer);
    var HSFBA = std.heap.FixedBufferAllocator.init(&PatternsBuffer);
    defer HSFBA.reset();

    var PatternsFile: std.fs.File = undefined;
    defer ScratchFBA.reset();

    // Read patterns path
    var ArgIter = try std.process.argsWithAllocator(ScratchFBA.allocator());
    defer ArgIter.deinit();
    if (!ArgIter.skip()) {
        unreachable;
    }
    const PatternsPathZ = try ArgIter.next(ScratchFBA.allocator()) orelse unreachable;

    // Open file
    PatternsFile = try std.fs.cwd().openFile(PatternsPathZ, .{});

    // Get pattern count
    var nPatterns: usize = 0;
    {
        const Reader = PatternsFile.reader();
        while (true) {
            const Byte = Reader.readByte() catch {
                break; // NOTE(cjb): Possibility of missing last pattern here..
            };
            if (Byte == '\n') {
                nPatterns += 1;
            }
        }
    }

    // Allocate Pattern, Flag, and ID buffer(s)
    var PatternsZ = try HSFBA.allocator().alloc([*c]u8, nPatterns);
    var Flags = try HSFBA.allocator().alloc(c_uint, nPatterns);
    var IDs = try HSFBA.allocator().alloc(c_uint, nPatterns);

    try PatternsFile.seekTo(0);
    var PatternIndex: c_uint = 0;
    const FileStat = try PatternsFile.stat();
    const MaxRead = FileStat.size;
    var Data = try PatternsFile.reader().readUntilDelimiterOrEofAlloc(ScratchFBA.allocator(), '\n', MaxRead);
    while (Data != null) : (PatternIndex += 1) {
        var PatternBuf = try HSFBA.allocator().alloc(u8, Data.?.len + 1);
        std.mem.copy(u8, PatternBuf, Data.?);
        PatternBuf[Data.?.len] = 0;
        PatternsZ[PatternIndex] = PatternBuf.ptr;
        Flags[PatternIndex] = c.HS_FLAG_DOTALL | c.HS_FLAG_CASELESS | c.HS_FLAG_SOM_LEFTMOST;
        IDs[PatternIndex] = PatternIndex;

        Data = try PatternsFile.reader().readUntilDelimiterOrEofAlloc(ScratchFBA.allocator(), '\n', MaxRead);
    }

    std.debug.print("Serializing Patterns: \n---------------------\n", .{});
    for (PatternsZ) |Pat| {
        std.debug.print("{s}\n", .{Pat});
    }

    var Database: ?*c.hs_database_t = null;
    var CompileError: ?*c.hs_compile_error_t = null;
    if (c.hs_compile_multi(PatternsZ.ptr, Flags.ptr, IDs.ptr, PatternIndex, c.HS_MODE_BLOCK, null, &Database, &CompileError) != c.HS_SUCCESS) {
        std.debug.print("{s}\n", .{CompileError.?.message});
        _ = c.hs_free_compile_error(CompileError);
        unreachable;
    }

    var Bytes: [*c]u8 = undefined;
    var Length: usize = undefined;
    if (c.hs_serialize_database(Database, &Bytes, &Length) != c.HS_SUCCESS) {
        unreachable;
    }

    var DeserializedSize: usize = undefined;
    if (c.hs_serialized_database_size(Bytes, Length,
            &DeserializedSize) != c.HS_SUCCESS)
    {
        unreachable;
    }

    var ArtifactHeader: gracie.gracie_artifact_header = undefined;
    ArtifactHeader.SerializedDatabaseSize = Length;
    ArtifactHeader.DeserializedDatabaseSize = DeserializedSize;

    const DatabaseFile = try std.fs.cwd().createFile("data/gracie.bin.0.0.1", .{});
    _ = try DatabaseFile.write(
        @ptrCast([*]u8, &ArtifactHeader)[0 .. @sizeOf(gracie.gracie_artifact_header)]);
    const BytesWritten = try DatabaseFile.write(Bytes[0..Length]);
    if (BytesWritten != Length) {
        unreachable;
    }
}
