const std = @import("std");
const common = @import("common.zig");
const c = @cImport({
    @cInclude("hs.h");
});

const array_list = std.ArrayList;

pub fn main() !void
{
    var Ally = std.heap.page_allocator;
    var ArgIter = try std.process.argsWithAllocator(Ally);
    defer ArgIter.deinit();
    if (!ArgIter.skip())
    {
        unreachable;
    }
    const ConfPathZ = ArgIter.next() orelse unreachable;
    const ArtiPathZ = ArgIter.next() orelse unreachable;

    try CreateArtifact(Ally, ConfPathZ, ArtiPathZ);
}

pub fn CreateArtifact(Ally: std.mem.Allocator, ConfPathZ: []const u8,
    ArtiPathZ: []const u8) !void
{

//
// Compute absolute path to config's parent dir
//

    // Try normalize arg absolute path

    var AbsConfPathBuf: [std.os.PATH_MAX]u8 = undefined;
    const AbsConfigPath = try std.fs.realpath(ConfPathZ, &AbsConfPathBuf);

    // Split path on '/', throw the filename away and grab everything but filename.

    var SplitAbsConfigPath = std.mem.splitBackwards(u8, AbsConfigPath, "/");
    _ = SplitAbsConfigPath.next();
    const AbsConfigDir = SplitAbsConfigPath.rest();

    // Read conf file in it's entirety then parse

    const FigF = try std.fs.cwd().openFile(ConfPathZ, .{});
    var ConfBytes = try FigF.reader().readAllAlloc(Ally, 1024*10); // 10kib should be enough
    defer Ally.free(ConfBytes);
    var Parser = std.json.Parser.init(Ally, false); const ParseTree = try Parser.parse(ConfBytes);
    const PyIncludePath = ParseTree.root.Object.get("PyIncludePath") orelse unreachable;
    const Extractors = ParseTree.root.Object.get("ExtractorDefinitions") orelse unreachable;

//
// Create artifact file and write initial header.
//

    // Create artifact file at path provided as second command line arg

    const ArtiF = try std.fs.cwd().createFile(ArtiPathZ, .{});

    //TODO(cjb): Be path agnostic here i.e. normalize to abs path but ignore if absoulute

    const AbsIncludePath = try std.fs.path.join(Ally, &[_][]const u8{AbsConfigDir,
        PyIncludePath.String});

    // Temp. open include dir so we can get count of TOP LEVEL '.py' files NOTE(cjb): recursive?

    var PyIncludeDir = try std.fs.openIterableDirAbsolute(AbsIncludePath,
        .{.access_sub_paths=true, .no_follow=true});
    const nPyModules = try CountFilesInDirWithExtension(PyIncludeDir, ".py");
    defer PyIncludeDir.close();

    var ArtiHeader = common.arti_header{
        .nPyModules = nPyModules,
        .nExtractorDefs = Extractors.Array.items.len,
    };
    try ArtiF.writer().writeStruct(ArtiHeader);

//
// Read python module data
//

    // Initialize module names list

    var PyModuleNames = array_list([]const u8).init(Ally);
    defer
    {
        for (PyModuleNames.items) |NameBuf| Ally.free(NameBuf);
        PyModuleNames.deinit();
    }

    var PyIncludeDirIter = PyIncludeDir.iterate();
    var PyIncludeDirEntry = try PyIncludeDirIter.next();
    while (PyIncludeDirEntry != null) : (PyIncludeDirEntry = try PyIncludeDirIter.next())
    {
        if (!std.mem.eql(u8, std.fs.path.extension(PyIncludeDirEntry.?.name), ".py"))
        {
            continue;
        }

        // Open source file, read plugin bytes and compute stripped basename.

        const AbsPyModulePath = try std.fs.path.join(Ally, &[_][]const u8{AbsIncludePath,
            PyIncludeDirEntry.?.name});
        const PySourceF = try std.fs.openFileAbsolute(AbsPyModulePath, .{});
        var PySourceBytes = try PySourceF.reader().readAllAlloc(Ally, 1024*10);
        defer Ally.free(PySourceBytes); // Don't need to hold onto these after serialization.

        // Write header, module name, and source bytes

        const BaseName = std.fs.path.basename(PyIncludeDirEntry.?.name);
        const ModuleName = std.fs.path.stem(BaseName);
        const PyModuleHeader = common.arti_py_module_header{
            .nPyNameBytes = ModuleName.len,
            .nPySourceBytes = PySourceBytes.len,
        };
        try ArtiF.writer().writeStruct(PyModuleHeader);
        try ArtiF.writer().writeAll(ModuleName);
        try ArtiF.writer().writeAll(PySourceBytes);

        // Lastly, commit module name to list as it will be required later to map the module which a
        //  category specifies to an index within this list.

        var ModuleNameBuf = try Ally.alloc(u8, ModuleName.len);
        for (ModuleName) |Byte, Index| ModuleNameBuf[Index] = Byte;
        try PyModuleNames.append(ModuleNameBuf);
    }

    // TODO(cjb): Breif desc about what is going on here...

    for (Extractors.Array.items) |Extractor|
    {
        // Build up lists of patterns, flags, and IDs from one or more categories. These three lists
        //  are all required to compile a hyperscan database.

        var PatternsZ = array_list(?[* :0]u8).init(Ally);
        var Flags = array_list(c_uint).init(Ally);
        var IDs = array_list(c_uint).init(Ally);
        defer
        {
            PatternsZ.deinit();
            Flags.deinit();
            IDs.deinit();
        }

        // Each category has an associated python plugin file path as well as a few patterns which
        //  are specific to a given category. For patterns this logic simply writes to the realavent
        //  list used during the hs_compile_multi call.

        var Categories = Extractor.Object.get("Categories") orelse unreachable;
        for (Categories.Array.items) |Category|
        {

            // Parse JSON patterns

            const nExistingPatterns = PatternsZ.items.len;
            const JSONPatterns = Category.Object.get("Patterns") orelse unreachable;
            for (JSONPatterns.Array.items) |Pattern, PatternIndex|
            {
                // Allocate space for pattern + termiantor, copy existing pattern and drop in
                //  the termination byte.
                // NOTE(cjb): HS expects a null terminated string...

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

        // Compile and serialize hyperscan database

        var Database: ?*c.hs_database_t = null;
        var CompileError: ?*c.hs_compile_error_t = null;
        if (c.hs_compile_multi(PatternsZ.items.ptr, Flags.items.ptr,
                IDs.items.ptr, @intCast(c_uint, PatternsZ.items.len), c.HS_MODE_BLOCK,
                null, &Database, &CompileError) != c.HS_SUCCESS)
        {
            std.debug.print("{s}\n", .{CompileError.?.message});
            _ = c.hs_free_compile_error(CompileError);
            return error.HSCompile;
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
        const Country = Extractor.Object.get("Country") orelse unreachable;
        const Language = Extractor.Object.get("Language") orelse unreachable;
        const ExtractorName = Extractor.Object.get("Name") orelse unreachable;

        // Verify country and langauge are digraphs
        if ((Country.String.len != 2) or
            (Language.String.len != 2))
        {
            unreachable;
        }

        const DefHeader = common.arti_def_header{
            .nExtractorNameBytes = ExtractorName.String.len,
            .DatabaseSize = nSerializedDBBytes,
            .nCategories = Categories.Array.items.len,
        };
        try ArtiF.writer().writeStruct(DefHeader);
        try ArtiF.writeAll(Country.String);
        try ArtiF.writeAll(Language.String);
        try ArtiF.writeAll(ExtractorName.String);
        try ArtiF.writeAll(SerializedDBBytes.?[0 .. nSerializedDBBytes]);

        for (Categories.Array.items) |Cat|
        {
            const Patterns = Cat.Object.get("Patterns") orelse unreachable;
            const CatName = Cat.Object.get("Name") orelse unreachable;
            const ResolvesWith = Cat.Object.get("ResolvesWith") orelse unreachable;

            if (std.mem.eql(u8, ResolvesWith.String, "script"))
            {
                // Read module name and compute index of MainPyModule within PyModuleNames.

                const MainPyModule = Cat.Object.get("MainPyModule") orelse unreachable;
                const MainPyModuleNoExt = std.fs.path.stem(MainPyModule.String);
                var MainModuleIndex: isize = undefined;
                for (PyModuleNames.items) |ModuleName, ModuleIndex|
                {
                    if (std.mem.eql(u8, MainPyModuleNoExt, ModuleName))
                    {
                        MainModuleIndex = @intCast(isize, ModuleIndex);
                    }
                }
                std.debug.assert(MainModuleIndex != -1);

                const CatHeader = common.arti_cat_header{
                    .nCategoryNameBytes = CatName.String.len,
                    .nCategoryConditionBytes = 0,
                };

                try ArtiF.writer().writeStruct(CatHeader);
                try ArtiF.writeAll(CatName.String);
                try ArtiF.writeAll(@ptrCast([*]const u8, &Patterns.Array.items.len)[0 .. @sizeOf(usize)]);
                try ArtiF.writeAll(@ptrCast([*]const u8, &MainModuleIndex)[0 .. @sizeOf(isize)]);
                try ArtiF.writeAll(@ptrCast([*]const u8, &common.arti_cat_resolves_with.Script)[0 .. @sizeOf(c_int)]);
            }
            else if (std.mem.eql(u8, ResolvesWith.String, "conditions"))
            {
                const MainModuleIndex: isize = -1;
                const Conditions = Cat.Object.get("Conditions") orelse unreachable;
                const CatHeader = common.arti_cat_header{
                    .nCategoryNameBytes = CatName.String.len,
                    .nCategoryConditionBytes = Conditions.String.len,
                };

                try ArtiF.writer().writeStruct(CatHeader);
                try ArtiF.writeAll(CatName.String);
                try ArtiF.writeAll(Conditions.String);
                try ArtiF.writeAll(@ptrCast([*]const u8, &Patterns.Array.items.len)[0 .. @sizeOf(usize)]);
                try ArtiF.writeAll(@ptrCast([*]const u8, &MainModuleIndex)[0 .. @sizeOf(isize)]);
                try ArtiF.writeAll(@ptrCast([*]const u8, &common.arti_cat_resolves_with.Conditions)[0 .. @sizeOf(c_int)]);
            }
            else
            {
                std.log.err("Category '{s}' has invalid ResolvesWith: {s}",
                    .{CatName.String, ResolvesWith.String});
                return error.InvalidResolvesWith;
            }

        }
    }
}

fn CountFilesInDirWithExtension(IDir: std.fs.IterableDir, Extension: []const u8) !usize
{
    var Result: usize = 0;
    var Iterator = IDir.iterate();
    var Entry = try Iterator.next();
    while (Entry != null) : (Entry = try Iterator.next())
    {
        if (std.mem.eql(u8, std.fs.path.extension(Entry.?.name), Extension))
        {
            Result += 1;
        }
    }
    return Result;
}
