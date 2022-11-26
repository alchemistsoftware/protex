const std = @import("std");

const c = @cImport({
    @cInclude("hs.h");
    @cInclude("stdio.h");
});

pub fn main() !void {
    var ScratchBuffer: [1024]u8 = undefined;
    var PatternsBuffer: [1024]u8 = undefined;
    var ScratchFBA = std.heap.FixedBufferAllocator.init(&ScratchBuffer);
    var PatternsFBA = std.heap.FixedBufferAllocator.init(&PatternsBuffer);

    var ArgsIterator = try std.process.argsWithAllocator(ScratchFBA.allocator());
    if (!ArgsIterator.skip()) {
        return;
    }
    const PatternsPathZ = ArgsIterator.next();
    const File = try std.fs.cwd().openFile(PatternsPathZ.?, .{});
    ArgsIterator.deinit();
    ScratchFBA.reset();

    var nPatterns: usize = 0;
    while (true) {
        const Byte = File.reader().readByte() catch {
            break; // Handle EOF == nPatterns + 1???
        };
        if (Byte == '\n') {
            nPatterns += 1;
        }
    }

    var PatternsZ = try PatternsFBA.allocator().alloc([*:0]u8, nPatterns);
    var Flags = try PatternsFBA.allocator().alloc(c_uint, nPatterns);
    var IDs = try PatternsFBA.allocator().alloc(c_uint, nPatterns);

    try File.seekTo(0);
    var PatternIndex: c_uint = 0;
    const FileStat = try File.stat();
    const MaxRead = FileStat.size;
    var Data = try File.reader().readUntilDelimiterOrEofAlloc(ScratchFBA.allocator(), '\n', MaxRead);
    while (Data != null) : (Data = try File.reader().readUntilDelimiterOrEofAlloc(ScratchFBA.allocator(), '\n', MaxRead)) {
        var PatternBuf: []u8 = try PatternsFBA.allocator().alloc(u8, Data.?.len + 1);
        std.mem.copy(u8, PatternBuf, Data.?);
        PatternBuf[Data.?.len] = 0;
        PatternsZ[PatternIndex] = PatternBuf[0..Data.?.len :0];
        Flags[PatternIndex] = c.HS_FLAG_DOTALL;
        IDs[PatternIndex] = PatternIndex;
        PatternIndex += 1;
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
        return;
    }

    var Bytes: [*c]u8 = undefined;
    var Length: usize = undefined;
    _ = c.hs_serialize_database(Database, &Bytes, &Length);

    const DatabaseFile = try std.fs.cwd().createFile("data/db.bin", .{});
    _ = try DatabaseFile.write(Bytes[0..Length]);
}
