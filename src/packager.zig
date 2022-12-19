const std = @import("std");
const gracie = @import("gracie.zig");

const c = @cImport({
    @cInclude("hs.h");
});

pub fn main() !void {
    // Allocate a scratch and patterns buffer.
    var PA = std.heap.page_allocator;

    var ConfFile: std.fs.File = undefined;

    // Read patterns path
    var ArgIter = try std.process.argsWithAllocator(PA);
    defer ArgIter.deinit();
    if (!ArgIter.skip()) {
        unreachable;
    }
    const PatternsPathZ = try ArgIter.next(PA) orelse unreachable;

    // Open file
    ConfFile = try std.fs.cwd().openFile(PatternsPathZ, .{});

    // Parse file
    var Parser = std.json.Parser.init(PA, false);
    var ConfBytes = try ConfFile.reader().readAllAlloc(PA, 1024*5);

    const ParseTree = try Parser.parse(ConfBytes);
    var Extractors = ParseTree.root.Object.get("extractors") orelse unreachable;
    var FirstExtractor = Extractors.Array.items[0].Object;
    var Patterns = FirstExtractor.get("categories").?.Array.items[0].Object.get("patterns").?.Array;

    // Get pattern count
    var nPatterns = Patterns.items.len;

    // Allocate Pattern, Flag, and ID buffer(s)
    var PatternsZ = try PA.alloc([*c]u8, nPatterns);
    var Flags = try PA.alloc(c_uint, nPatterns);
    var IDs = try PA.alloc(c_uint, nPatterns);

    for (Patterns.items) |Pattern, PatternIndex|
    {
        var PatternBuf = try PA.alloc(u8, Pattern.String.len + 1);
        std.mem.copy(u8, PatternBuf, Pattern.String);
        PatternBuf[Pattern.String.len] = 0;
        PatternsZ[PatternIndex] = PatternBuf.ptr;
        Flags[PatternIndex] = c.HS_FLAG_DOTALL | c.HS_FLAG_CASELESS | c.HS_FLAG_SOM_LEFTMOST | c.HS_FLAG_UTF8;
        IDs[PatternIndex] = @intCast(c_uint, PatternIndex);
    }

    std.debug.print("Serializing Patterns:\n", .{});
    for (PatternsZ) |Pat| {
        std.debug.print("{s}\n", .{Pat});
    }

    var Database: ?*c.hs_database_t = null;
    var CompileError: ?*c.hs_compile_error_t = null;
    if (c.hs_compile_multi(PatternsZ.ptr, Flags.ptr, IDs.ptr, @intCast(c_uint, nPatterns),
                c.HS_MODE_BLOCK, null, &Database, &CompileError) != c.HS_SUCCESS) {
        std.debug.print("{s}\n", .{CompileError.?.message});
        _ = c.hs_free_compile_error(CompileError);
        unreachable;
    }
    std.debug.print("Pattern db compile success.\n", .{});

    var SerializedDBBytes: [*c]u8 = undefined;
    var nSerializedDBBytes: usize = undefined;
    if (c.hs_serialize_database(Database, &SerializedDBBytes, &nSerializedDBBytes) != c.HS_SUCCESS) {
        unreachable;
    }

    var DeserializedSize: usize = undefined;
    if (c.hs_serialized_database_size(SerializedDBBytes, nSerializedDBBytes,
            &DeserializedSize) != c.HS_SUCCESS)
    {
        unreachable;
    }

    var ArtifactHeader: gracie.gracie_artifact_header = undefined;
    ArtifactHeader.DatabaseSize = DeserializedSize;

    const ArtifactFile = try std.fs.cwd().createFile("data/gracie.bin.0.0.1", .{});
    _ = try ArtifactFile.write(
        @ptrCast([*]u8, &ArtifactHeader)[0 .. @sizeOf(gracie.gracie_artifact_header)]);
    const BytesWritten = try ArtifactFile.write(SerializedDBBytes[0..nSerializedDBBytes]);
    if (BytesWritten != nSerializedDBBytes) {
        unreachable;
    }
}
