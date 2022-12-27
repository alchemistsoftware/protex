const std = @import("std");
const common = @import("common.zig");
const c = @cImport({
    @cInclude("hs.h");
});

const array_list = std.ArrayList;

pub fn main() !void
{
    // Allocate a scratch and patterns buffer.
    var PA = std.heap.page_allocator;

    // Read patterns path
    var ArgIter = try std.process.argsWithAllocator(PA);
    defer ArgIter.deinit();
    if (!ArgIter.skip()) {
        unreachable;
    }
    // Open config file
    const ConfPathZ = ArgIter.next() orelse unreachable;
    const ConfFile = try std.fs.cwd().openFile(ConfPathZ, .{});

    // Absolute path to config dir
    var AbsConfPathBuf: [std.os.PATH_MAX]u8 = undefined;
    const AbsConfigPath = try std.fs.realpath(ConfPathZ, &AbsConfPathBuf);
    var SplitAbsConfigPath = std.mem.splitBackwards(u8, AbsConfigPath, "/");
    _ = SplitAbsConfigPath.next();
    const AbsConfigDir = SplitAbsConfigPath.rest();

    // Parse file
    var Parser = std.json.Parser.init(PA, false);
    var ConfBytes = try ConfFile.reader().readAllAlloc(PA, 1024*5); // 5kib should be enough
    defer PA.free(ConfBytes);
    const ParseTree = try Parser.parse(ConfBytes);
    const Extractors = ParseTree.root.Object.get("extractors") orelse unreachable;
    for (Extractors.Array.items) |Extractor|
    {
        var ExtractorName = Extractor.Object.get("name") orelse unreachable;

        var PatternsZ = array_list(?[* :0]u8).init(PA);
        defer PatternsZ.deinit();
        var Flags = array_list(c_uint).init(PA);
        defer Flags.deinit();
        var IDs = array_list(c_uint).init(PA);
        defer IDs.deinit();

        var PatternCount: usize = 0;

        var Categories = Extractor.Object.get("categories") orelse unreachable;
        for (Categories.Array.items) |Category|
        {
            // Build path to plugin file
            const ConfRelSourcePath = Category.Object.get("py_source_path").?.String;
            const AbsSourcePath = try std.fs.path.join(PA, &[_][]const u8{AbsConfigDir,
                ConfRelSourcePath});

            // Open and read plugin bytes
            const PluginSourceFile = try std.fs.cwd().openFile(AbsSourcePath, .{});
            var PluginSourceBytes = try
                PluginSourceFile.reader().readAllAlloc(PA, 1024*5); // Ditto
            _ = PluginSourceBytes;

            const Patterns = Category.Object.get("patterns").?.Array;

            // Get pattern count
            for (Patterns.items) |Pattern, PatternIndex|
            {
                var PatternBuf = try PA.alloc(u8, Pattern.String.len + 1);
                std.mem.copy(u8, PatternBuf, Pattern.String);
                PatternBuf[Pattern.String.len] = 0;
                try PatternsZ.append(PatternBuf[0.. Pattern.String.len :0]);
                try Flags.append(c.HS_FLAG_DOTALL | c.HS_FLAG_CASELESS |
                    c.HS_FLAG_SOM_LEFTMOST | c.HS_FLAG_UTF8);
                try IDs.append(@intCast(c_uint, PatternIndex + PatternCount));
            }
            PatternCount += Patterns.items.len;
        }

        // Database serialization
        var Database: ?*c.hs_database_t = null;
        var CompileError: ?*c.hs_compile_error_t = null;
        if (c.hs_compile_multi(PatternsZ.items.ptr, Flags.items.ptr, IDs.items.ptr, @intCast(c_uint, Patterns.items.len),
                    c.HS_MODE_BLOCK, null, &Database, &CompileError) != c.HS_SUCCESS)
        {
            std.debug.print("{s}\n", .{CompileError.?.message});
            _ = c.hs_free_compile_error(CompileError);
            unreachable;
        }

        var SerializedDBBytes: [*c]u8 = undefined;
        var nSerializedDBBytes: usize = undefined;
        if (c.hs_serialize_database(Database, &SerializedDBBytes,
                &nSerializedDBBytes) != c.HS_SUCCESS) {
            unreachable;
        }

        var DeserializedSize: usize = undefined;
        if (c.hs_serialized_database_size(SerializedDBBytes, nSerializedDBBytes,
                &DeserializedSize) != c.HS_SUCCESS)
        {
            unreachable;
        }

        const ExtractionCtxHeader = common.gracie_extraction_ctx{
            .nExtractorNameBytes=ExtractorName.len,
            .DatabaseSize=DeserializedSize,
            .nPatterns=PatternCount,
            .nCategories=Categories.Array.items.len,
        };

        const ArtifactFile = try std.fs.cwd().createFile("data/gracie.bin.0.0.1", .{});
        try ArtifactFile.writer().writeStruct(ExtractionCtxHeader);
        const BytesWritten = try ArtifactFile.write(SerializedDBBytes[0..nSerializedDBBytes]);
        if (BytesWritten != nSerializedDBBytes) {
            unreachable;
        }
        for (IDs) |ID|
        {
            _ = try ArtifactFile.write(@ptrCast([*]const u8, &ID)[0..@sizeOf(c_uint)]);
            _ = try ArtifactFile.write(@ptrCast([*]const u8,
                    &@intCast(c_uint, CategoryIndex))[0..@sizeOf(c_uint)]);
        }
    }
}
