const std = @import("std");
const common = @import("common.zig");
const c = @cImport({
    @cInclude("hs.h");
});

const array_list = std.ArrayList;

//
// Visual layout of a gracie artifact
//

//TODO(cjb): Currently python source code is serialized per category, however there may be an
//  instance where it is desired to have a single plugin shared across multiple categories or even
//  extractors. Don't replicate source bytes.
// TODO(cjb): Support multipule plugins per category.

// |--------Artifact header---------|
// |Extraction ctx count (usize)    |
// |--------------------------------|
//
//     |---Extraction context header----|
//     | N extractor name bytes (usize) |
//     | N database bytes (usize)       |
//     | N categories (usize)           |
//     |----Extraction context data-----|
//     | Country (2 bytes)              |
//     | Language (2 bytes)             |
//     | Extractor name (nBytes)        |
//     | HS database (nbytes)           |
//     |--------------------------------|
//
//         |--------Category header---------|
//         | N category name bytes (usize)  |
//         | N plugin source bytes (usize)  |
//         | N patterns (usize)             |
//         |---------Category data----------|
//         | Category name (nbytes)         |
//         | Plugin source (nBytes)         |
//         |--------------------------------|
//
//         |--------Category header---------|
//         |              ...               |
//         |--------------------------------|
//
//     |---Extraction context header----|
//     |             ...                |
//     |--------------------------------|
//

pub fn main() !void
{
    // Use page allocator for most allocations
    var Ally = std.heap.page_allocator;

    // Parse command line args
    var ArgIter = try std.process.argsWithAllocator(Ally);
    defer ArgIter.deinit();
    if (!ArgIter.skip())
    {
        unreachable;
    }

//
// Compute absolute path to config's parent dir
//
    const ConfPathZ = ArgIter.next() orelse unreachable;

    // Try normalize arg absolute path
    var AbsConfPathBuf: [std.os.PATH_MAX]u8 = undefined;
    const AbsConfigPath = try std.fs.realpath(ConfPathZ, &AbsConfPathBuf);

    // Split path on '/', throw the filename away and grab everything but filename.
    var SplitAbsConfigPath = std.mem.splitBackwards(u8, AbsConfigPath, "/");
    _ = SplitAbsConfigPath.next();
    const AbsConfigDir = SplitAbsConfigPath.rest();

//
// Parse the config file.
//
    const FigF = try std.fs.cwd().openFile(ConfPathZ, .{});

    // Obtain parser and read conf file in it's entirety.
    var Parser = std.json.Parser.init(Ally, false);
    var ConfBytes = try FigF.reader().readAllAlloc(Ally, 1024*5); // 5kib should be enough
    defer Ally.free(ConfBytes);

    // Parse bytes
    const ParseTree = try Parser.parse(ConfBytes);
    const Extractors = ParseTree.root.Object.get("extractors") orelse unreachable;

//
// Create an artifact and write header before moving on.
//
    const ArtiPathZ = ArgIter.next() orelse unreachable;
    const ArtiF = try std.fs.cwd().createFile(ArtiPathZ, .{});
    var ArtiHeader = common.gracie_arti_header{.nExtractorDefs = Extractors.Array.items.len};
    try ArtiF.writer().writeStruct(ArtiHeader);
    // TODO(cjb): Breif desc about what is going on here...
    for (Extractors.Array.items) |Extractor|
    {
        // Build up lists of patterns, flags, and IDs from one or more categories. These three lists
        // are all required to compile a hyperscan database.
        var PatternsZ = array_list(?[* :0]u8).init(Ally);
        var Flags = array_list(c_uint).init(Ally);
        var IDs = array_list(c_uint).init(Ally);
        defer
        {
            //for (PatternsZ.items) |Pattern| Ally.free(Pattern.?); FIXME(cjb)
            PatternsZ.deinit();
            Flags.deinit();
            IDs.deinit();
        }

        // List of n python source files
        // TODO(cjb): This will need to be hoisted... see common.zig
        var Plugins = array_list([]u8).init(Ally);
        defer
        {
            for (Plugins.items) |Source| Ally.free(Source);
            Plugins.deinit();
        }

        // Each category has an associated python plugin file path as well as a few patterns which
        // are specific to a given category. For patterns this logic simply writes to the realavent
        // list used during the hs_compile_multi call. Python source bytes are written to a seperate
        // list.
        var Categories = Extractor.Object.get("categories") orelse unreachable;
        for (Categories.Array.items) |Category|
        {
            // Build path to plugin file
            const ConfRelSourcePath = Category.Object.get("py_source_path").?.String;
            const AbsSourcePath = try std.fs.path.join(Ally, &[_][]const u8{AbsConfigDir,
                ConfRelSourcePath});

            // Open source file, read plugin bytes and append to plugin list.
            const PluginSourceF = try std.fs.cwd().openFile(AbsSourcePath, .{});
            var PluginSourceBytes = try
                PluginSourceF.reader().readAllAlloc(Ally, 1024*10); // 10kib source file cap...
            try Plugins.append(PluginSourceBytes);

            // Parse json patterns
            const nExistingPatterns = PatternsZ.items.len;
            const JSONPatterns = Category.Object.get("patterns") orelse unreachable;
            for (JSONPatterns.Array.items) |Pattern, PatternIndex|
            {
                // Allocate space for pattern + termiantor, copy existing pattern and drop in
                //  the termination byte. NOTE(cjb): HS expects a null terminated string...
                var PatternBuf = try Ally.alloc(u8, Pattern.String.len + 1);
                std.mem.copy(u8, PatternBuf, Pattern.String);
                PatternBuf[Pattern.String.len] = 0;

                // Append pattern, flag and it's id.
                try PatternsZ.append(PatternBuf[0.. Pattern.String.len :0]);
                try Flags.append(c.HS_FLAG_DOTALL | c.HS_FLAG_CASELESS |
                    c.HS_FLAG_SOM_LEFTMOST | c.HS_FLAG_UTF8);
                try IDs.append(@intCast(c_uint, PatternIndex + nExistingPatterns));
            }
        }
//
// Compile and serialize hyperscan database
//
        var Database: ?*c.hs_database_t = null;
        var CompileError: ?*c.hs_compile_error_t = null;
        if (c.hs_compile_multi(PatternsZ.items.ptr, Flags.items.ptr,
                IDs.items.ptr, @intCast(c_uint, PatternsZ.items.len), c.HS_MODE_BLOCK,
                null, &Database, &CompileError) != c.HS_SUCCESS)
        {
            std.debug.print("{s}\n", .{CompileError.?.message});
            _ = c.hs_free_compile_error(CompileError);
            unreachable;
        }
        defer
        {
            if (c.hs_free_database(Database) != c.HS_SUCCESS)
            {
                unreachable;
            }
        }
        var SerializedDBBytes: ?[*]u8 = undefined;
        var nSerializedDBBytes: usize = undefined;
        if (c.hs_serialize_database(Database,
                &SerializedDBBytes, &nSerializedDBBytes) != c.HS_SUCCESS)
        {
            unreachable;
        }
        defer std.heap.raw_c_allocator.free(SerializedDBBytes.?[0 .. nSerializedDBBytes]);

//
// Write extractor definition header and it's data. Then proceed to write the category
// headers and their data as well.
//
        // Snag country, langauge and extractor name.
        const Country = Extractor.Object.get("country") orelse unreachable;
        const Language = Extractor.Object.get("language") orelse unreachable;
        const ExtractorName = Extractor.Object.get("name") orelse unreachable;

        // Verify country and langauge lengths
        if ((Country.String.len != 2) or
            (Language.String.len != 2))
        {
            unreachable;
        }

        const DefHeader = common.gracie_extractor_def_header{
            .nExtractorNameBytes = ExtractorName.String.len,
            .DatabaseSize = nSerializedDBBytes,
            .nCategories = Categories.Array.items.len,
        };
        try ArtiF.writer().writeStruct(DefHeader);
        try ArtiF.writeAll(Country.String);
        try ArtiF.writeAll(Language.String);
        try ArtiF.writeAll(ExtractorName.String);
        try ArtiF.writeAll(SerializedDBBytes.?[0 .. nSerializedDBBytes]);

        for (Categories.Array.items) |Gory, GoryIndex|
        {
            const Patterns = Gory.Object.get("patterns") orelse unreachable;
            const GoryName = Gory.Object.get("name") orelse unreachable;
            const GoryHeader = common.gracie_extractor_cat_header{
                .nCategoryNameBytes = GoryName.String.len,
                .nPyPluginSourceBytes = Plugins.items[GoryIndex].len,
                .nPatterns = Patterns.Array.items.len,
            };

            try ArtiF.writer().writeStruct(GoryHeader);
            try ArtiF.writeAll(GoryName.String);
            try ArtiF.writeAll(Plugins.items[GoryIndex]);
        }
    }
}
