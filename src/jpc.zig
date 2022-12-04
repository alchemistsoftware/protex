const std = @import("std");

const c = @cImport({
    @cInclude("hs.h");
    @cInclude("stdio.h");
});

const job_posting_classifier = extern struct {
    Database: ?*c.hs_database_t,
    Scratch: ?*c.hs_scratch_t,
};

pub const JPC_SUCCESS: c_int = 0; // Call was executed successfully
pub const JPC_INVALID: c_int = -1; // Bad paramater was passed
pub const JPC_UNKNOWN_ERROR: c_int = -2; // Unhandled internal error
pub const JPC_NOMEM: c_int = -3; // A memory allocation failed

fn HSSuccessOrErr(Writer: std.fs.File.Writer, HSReturnCode: c_int) !void {
    switch (HSReturnCode) {
        c.HS_SUCCESS => return,
        c.HS_INVALID => Writer.print("HS_INVALID\n", .{}) catch {},
        c.HS_NOMEM => Writer.print("HS_NOMEM\n", .{}) catch {},
        c.HS_SCAN_TERMINATED => Writer.print("HS_SCAN_TERMINATED\n", .{}) catch {},
        c.HS_COMPILER_ERROR => Writer.print("HS_COMPILER_ERROR\n", .{}) catch {},
        c.HS_DB_VERSION_ERROR => Writer.print("HS_DB_VERSION_ERROR\n", .{}) catch {},
        c.HS_DB_PLATFORM_ERROR => Writer.print("HS_DB_PLATFORM_ERROR\n", .{}) catch {},
        c.HS_DB_MODE_ERROR => Writer.print("HS_DB_MODE_ERROR\n", .{}) catch {},
        c.HS_BAD_ALIGN => Writer.print("HS_BAD_ALIGN\n", .{}) catch {},
        c.HS_BAD_ALLOC => Writer.print("HS_BAD_ALLOC\n", .{}) catch {},
        c.HS_SCRATCH_IN_USE => Writer.print("HS_SCRATCH_IN_USE\n", .{}) catch {},
        c.HS_ARCH_ERROR => Writer.print("HS_ARCH_ERROR\n", .{}) catch {},
        c.HS_INSUFFICIENT_SPACE => Writer.print("HS_INSUFFICIENT_SPACE\n", .{}) catch {},
        c.HS_UNKNOWN_ERROR => Writer.print("HS_UNKNOWN_ERROR\n", .{}) catch {},
        else => unreachable,
    }
    return error.Error;
}

//const jpc_alloc = *const fn(Size: usize) ?*anyopaque;
//const jpc_free = *const fn(Ptr: ?*anyopaque) void;

// TODO(cjb): pass me acutal allocator...
export fn JPCInit(JPC: ?*job_posting_classifier, JPCFixedBuffer: ?*anyopaque, JPCFixedBufferSize: usize,
    ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    const Writer = std.io.getStdErr().writer();

    var ByteBuffer = @ptrCast([*]u8, JPCFixedBuffer.?);
    var FBA = std.heap.FixedBufferAllocator.init(ByteBuffer[0..JPCFixedBufferSize]);

    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }
    const ArtifactFile = std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{}) catch |Err|
    {
        switch (Err)
        {
            error.FileNotFound => return JPC_INVALID,
            else => Writer.print("{}\n", .{Err}) catch {},
        }
        unreachable;
    };

    const FileStat = ArtifactFile.stat() catch |Err|
    {
        switch(Err)
        {
            else => Writer.print("{}\n", .{Err}) catch {},
        }
        unreachable;
    };

    const FSize = FileStat.size;
    const SerializedBytes = ArtifactFile.reader().readAllAlloc(FBA.allocator(), FSize) catch |Err|
    {
        switch(Err)
        {
            error.OutOfMemory => return JPC_NOMEM,
            else => Writer.print("{}\n", .{Err}) catch {},
        }
        unreachable;
    };
    defer FBA.allocator().free(SerializedBytes);

    // TODO(cjb): hs_set_misc_allocator()

    var DBSize: usize = undefined;
    HSSuccessOrErr(Writer, c.hs_serialized_database_size(SerializedBytes.ptr, SerializedBytes.len,
            &DBSize)) catch
    {
        return JPC_UNKNOWN_ERROR;
    };

    var DBMem = FBA.allocator().alignedAlloc(u8, 8, DBSize) catch |Err|
    {
        switch(Err)
        {
            error.OutOfMemory => return JPC_NOMEM,
            else => Writer.print("{}\n", .{Err}) catch {},
        }
        unreachable;
    };

    JPC.?.Database = @ptrCast(*c.hs_database_t, DBMem);
    HSSuccessOrErr(Writer, c.hs_deserialize_database_at(SerializedBytes.ptr, SerializedBytes.len,
            JPC.?.Database)) catch
    {
        return JPC_UNKNOWN_ERROR;
    };

    // TODO(cjb): set allocator used for scratch
    JPC.?.Scratch = null;
    HSSuccessOrErr(Writer, c.hs_alloc_scratch(JPC.?.Database, &JPC.?.Scratch)) catch
    {
        return JPC_UNKNOWN_ERROR;
    };

    return JPC_SUCCESS;
}

fn EventHandler(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint, Ctx: ?*anyopaque)
    callconv(.C) c_int
{
    _ = id;
    _ = flags;

    const Writer = std.io.getStdErr().writer();
    const TextPtr = @ptrCast(?[*]u8, Ctx);
    Writer.print("Match: '{s}' (from: {d}, to: {d})\n", .{ TextPtr.?[from..to], from, to }) catch
    {};
    return 0;
}

export fn JPCExtract(JPC: ?*job_posting_classifier, Text: ?[*]u8, nTextBytes: c_uint) callconv(.C)
    c_int
{
    _ = JPC;
    const Writer = std.io.getStdErr().writer();

    if (c.hs_scan(JPC.?.Database, Text, nTextBytes, 0, JPC.?.Scratch, EventHandler, Text) !=
        c.HS_SUCCESS)
    {
        Writer.print("Unable to scan input buffer.\n", .{}) catch {};
        return JPC_UNKNOWN_ERROR;
    }

    return JPC_SUCCESS;
}

export fn JPCDeinit(JPC: ?*job_posting_classifier) callconv(.C) c_int {
    _ = c.hs_free_scratch(JPC.?.Scratch);

    return JPC_SUCCESS;
}

test "Check hs is working" {}
