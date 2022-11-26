const std = @import("std");

const c = @cImport({
    @cInclude("hs.h");
    @cInclude("stdio.h");
});

const jpc = extern struct {
    Database: ?*c.hs_database_t,
};

export fn JPCInitialize(JPC: *jpc, ArtifactPathZ: [*:0]const u8) callconv(.C) void {
    var PathLen: usize = 0;
    while (ArtifactPathZ[PathLen] != 0) {
        PathLen += 1;
    }
    const F = std.fs.cwd().openFile(ArtifactPathZ[0..PathLen], .{}) catch {
        // failed to open file
        return;
    };
    var AA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer AA.deinit();

    const FileStat = F.stat() catch {
        // couldn't stat
        return;
    };
    const FSize = FileStat.size;

    const Bytes = F.reader().readAllAlloc(AA.allocator(), FSize) catch {
        // failed to read bytes
        return;
    };

    std.debug.print("LOADING DB...\n", .{});
    // TODO(cjb): set allocator...
    _ = c.hs_deserialize_database(Bytes.ptr, Bytes.len, &JPC.*.Database);
}

fn EventHandler(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint, ctx: ?*anyopaque) callconv(.C) c_int {
    _ = id;
    _ = flags;
    _ = ctx;
    _ = c.printf("Match (from: %llu, to: %llu)\n", from, to);
    return 0;
}

export fn Extract(Text: *u8, nTextBytes: c_uint) callconv(.C) c_int {
    _ = Text;
    _ = nTextBytes;

    //var Scratch: ?*c.hs_scratch_t = null;
    //if (c.hs_alloc_scratch(Database, &Scratch) != c.HS_SUCCESS) {
    //    _ = c.fprintf(c.stderr, "ERROR: Unable to allocate scratch space. Exiting.\n");
    //    _ = c.hs_free_database(Database);
    //    return -1;
    //}

    //_ = c.printf("Scanning %u bytes with Hyperscan\n", nTextBytes);
    //if (c.hs_scan(Database, Text, nTextBytes, 0, Scratch, EventHandler, Text) != c.HS_SUCCESS) {
    //    _ = c.fprintf(c.stderr, "ERROR: Unable to scan input buffer. Exiting.\n");
    //    _ = c.hs_free_scratch(Scratch);
    //    _ = c.hs_free_database(Database);
    //    return -1;
    //}

    //_ = c.hs_free_scratch(Scratch);
    //_ = c.hs_free_database(Database);

    return 100;
}

test "Check hs is working" {}
