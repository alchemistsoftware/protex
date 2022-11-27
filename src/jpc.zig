const std = @import("std");

const c = @cImport({
    @cInclude("hs.h");
    @cInclude("stdio.h");
});

const job_posting_classifier = extern struct {
    Database: ?*c.hs_database_t,
    Scratch: ?*c.hs_scratch_t,
};

const JPC_SUCCESS: c_int = 0; // Call was executed successfully
const JPC_INVALID: c_int = -1; // Bad paramater was passed
const JPC_UNKNOWN_ERROR: c_int = -2; // Unhandled internal error

fn HSSuccessOrErr(Writer: std.fs.File.Writer, HSReturnCode: c_int) !void {
    switch (HSReturnCode) {
        c.HS_SUCCESS => return,
        c.HS_INVALID => Writer.print("HS_INVALID\n", .{}) catch unreachable,
        c.HS_NOMEM => Writer.print("HS_NOMEM\n", .{}) catch unreachable,
        c.HS_SCAN_TERMINATED => Writer.print("HS_SCAN_TERMINATED\n", .{}) catch unreachable,
        c.HS_COMPILER_ERROR => Writer.print("HS_COMPILER_ERROR\n", .{}) catch unreachable,
        c.HS_DB_VERSION_ERROR => Writer.print("HS_DB_VERSION_ERROR\n", .{}) catch unreachable,
        c.HS_DB_PLATFORM_ERROR => Writer.print("HS_DB_PLATFORM_ERROR\n", .{}) catch unreachable,
        c.HS_DB_MODE_ERROR => Writer.print("HS_DB_MODE_ERROR\n", .{}) catch unreachable,
        c.HS_BAD_ALIGN => Writer.print("HS_BAD_ALIGN\n", .{}) catch unreachable,
        c.HS_BAD_ALLOC => Writer.print("HS_BAD_ALLOC\n", .{}) catch unreachable,
        c.HS_SCRATCH_IN_USE => Writer.print("HS_SCRATCH_IN_USE\n", .{}) catch unreachable,
        c.HS_ARCH_ERROR => Writer.print("HS_ARCH_ERROR\n", .{}) catch unreachable,
        c.HS_INSUFFICIENT_SPACE => Writer.print("HS_INSUFFICIENT_SPACE\n", .{}) catch unreachable,
        c.HS_UNKNOWN_ERROR => Writer.print("HS_UNKNOWN_ERROR\n", .{}) catch unreachable,
        else => unreachable,
    }

    return error.Error;
}

export fn JPCInitialize(JPC: *job_posting_classifier, ArtifactPathZ: [*c]const u8) callconv(.C) c_int
{
    const StdErr = std.io.getStdErr();
    defer StdErr.close();

    var AA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer AA.deinit();

    var Bytes: []u8 = undefined;
    defer AA.allocator().free(Bytes);
    {
        var PathLen: usize = 0;
        while (ArtifactPathZ[PathLen] != 0) {
            PathLen += 1;
        }

        const ArtifactFile = std.fs.cwd().openFile(ArtifactPathZ[0..PathLen], .{}) catch |Err| {
            switch (Err) {
                error.FileNotFound => return JPC_INVALID,
                else => {
                    StdErr.writer().print("{}\n", .{Err}) catch unreachable;
                    return JPC_UNKNOWN_ERROR;
                },
            }
        };

        const FileStat = ArtifactFile.stat() catch |Err| {
            StdErr.writer().print("{}\n", .{Err}) catch unreachable;
            return JPC_UNKNOWN_ERROR;
        };

        const FSize = FileStat.size;
        Bytes = ArtifactFile.reader().readAllAlloc(AA.allocator(), FSize) catch |Err| {
            StdErr.writer().print("{}\n", .{Err}) catch unreachable;
            return JPC_UNKNOWN_ERROR;
        };

        // TODO(cjb): set allocator... also allocates space for database
        JPC.Database = null;
        HSSuccessOrErr(StdErr.writer(),
            c.hs_deserialize_database(Bytes.ptr, Bytes.len, &JPC.Database))
            catch return JPC_UNKNOWN_ERROR;

        JPC.Scratch = null;
        HSSuccessOrErr(StdErr.writer(),
            c.hs_alloc_scratch(JPC.Database, &JPC.Scratch)) catch
        {
            _ = c.hs_free_database(JPC.Database);
            return JPC_UNKNOWN_ERROR;
        };
    }

    return JPC_SUCCESS;
}

fn EventHandler(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint, ctx: ?*anyopaque) callconv(.C) c_int {
    _ = id;
    _ = flags;
    _ = ctx;
    _ = c.printf("Match (from: %llu, to: %llu)\n", from, to);
    return 0;
}

export fn JPCExtract(JPC: *job_posting_classifier, Text: [*c]u8, nTextBytes: c_uint) callconv(.C) c_int {
    _ = JPC;

    const StdErr = std.io.getStdErr();
    defer StdErr.close();
    StdErr.writer().print("Text: {s}\n", .{Text[0..nTextBytes]}) catch unreachable;

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
