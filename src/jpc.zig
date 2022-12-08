const std = @import("std");

//TODO(cjb):
// - SlabAllocatorInit store a ref to the allocator so it doesn't need to be passed to alloc and
// free?
// - Some sort of set alloactor function/interface for jpc
// - How does jpc handle allocation without setting an allocator?

pub const slab_entry = extern struct
{
    Next: ?*slab_entry,
};

pub const slab = extern struct
{
    NextSlab: ?*slab,
    FreeList: ?*slab_entry,
    SlabStart: usize,
    Size: usize,
};

pub const slab_allocator = extern struct
{
    Buf: ?[*]u8,
    BufLen: usize,
    LeftOffset: usize,
    RightOffset: usize,
    SlabList: ?*slab,
    MetaSlab: ?*slab,
};

fn IsPowerOfTwo(X: usize) bool
{
    return (X & (X - 1)) == 0;
}

fn AlignBackward(Ptr: usize, Align: usize) usize
{
    std.debug.assert(IsPowerOfTwo(Align));

    var P: usize = Ptr;
    const A: usize = Align;

    // Same as (P % A) but faster as 'A' is a power of two
    const Modulo: usize = P & (A - 1);

    if (Modulo != 0)
    {
        P -= Modulo;
    }

    return (P);
}

fn AlignForward(Ptr: usize, Align: usize) usize
{
    std.debug.assert(IsPowerOfTwo(Align));

    var P: usize = Ptr;
    const A: usize = Align;

    // Same as (P % A) but faster as 'A' is a power of two
    const Modulo: usize = P & (A - 1);

    if (Modulo != 0)
    {
        P += A - Modulo;
    }

    return (P);
}

fn SlabInitAlign(A: ?*slab_allocator, S: ?*slab, Size: usize, Align: usize,
    IsMetaSlab: bool) void
{
    var PageBegin: usize = undefined;
    if (IsMetaSlab)
    {
        // Forward align 'Offset' to the specified alignment
        var CurrentPtr: usize = @intCast(usize, @ptrToInt(A.?.Buf)) + A.?.LeftOffset;
        var Offset: usize = AlignForward(CurrentPtr, Align);
        Offset -= @intCast(usize, @ptrToInt(A.?.Buf)); // Change to relative offset
        if (Offset + std.mem.page_size <= A.?.RightOffset)
        {
            PageBegin = @intCast(usize, @ptrToInt(A.?.Buf)) + Offset;
            A.?.LeftOffset = Offset + std.mem.page_size;
        }
        else
        {
            unreachable; // out of mem
        }
    }
    else
    {
        // Backward align 'Offset' to the specified alignment
        var CurrentPtr: usize = @intCast(usize, @ptrToInt(A.?.Buf)) + A.?.RightOffset;
        var Offset: usize = AlignBackward(CurrentPtr, Align);
        Offset -= @intCast(usize, @ptrToInt(A.?.Buf)); // Change to relative offset
        if (Offset - std.mem.page_size > A.?.LeftOffset)
        {
            PageBegin = @intCast(usize, @ptrToInt(A.?.Buf)) + Offset - std.mem.page_size;
            A.?.RightOffset = Offset - std.mem.page_size;
        }
        else
        {
            unreachable; // out of mem
        }
    }

    for (@intToPtr([*]u8, PageBegin)[0..std.mem.page_size]) |*Byte| Byte.* = 0;

    S.?.NextSlab = null;
    S.?.Size = Size;
    S.?.SlabStart = PageBegin;

    // TODO(cjb): Assert std.mem.page_size divides Size evenly
    var NumEntries: usize = (std.mem.page_size / Size);
    S.?.FreeList = @intToPtr(?*slab_entry, PageBegin + (NumEntries - 1) * Size); //@ptrCast(?*slab_entry, @alignCast(@alignOf(slab_entry), Ptr));
    var Current: ?*slab_entry = S.?.FreeList;

    std.debug.assert(NumEntries >= 4);
    var SlabEntryIndex: isize = @intCast(isize, NumEntries) - 1;
    while (SlabEntryIndex >= 0) : (SlabEntryIndex -= 1)
    {
        Current.?.Next = @intToPtr(?*slab_entry, S.?.SlabStart +
                                     @intCast(usize, SlabEntryIndex) * Size);
        Current = Current.?.Next;
    }
}

fn SlabInit(A: ?*slab_allocator, S: ?*slab, Size: usize, IsMetaSlab: bool) void {
    return SlabInitAlign(A, S, Size, 2*@sizeOf(?*anyopaque), IsMetaSlab);
}

fn SlabAlloc(S: ?*slab, Size: usize, NewLoc: *usize) bool
{
    var Result: bool = true;
    if ((S.?.Size != Size) or (S.?.FreeList == null))
    {
        Result = false;
    }
    else
    {
        NewLoc.* = @intCast(usize, @ptrToInt(S.?.FreeList));
        S.?.FreeList = S.?.FreeList.?.Next;
    }
    return (Result);
}

fn SlabFree(S: ?*slab, Location: usize) bool {
    var Result: bool = true;
    if ((Location < S.?.SlabStart) or (Location >= (S.?.SlabStart + std.mem.page_size)))
    {
        Result = false;
    }
    else
    {
        var NewEntry: *slab_entry = @intToPtr(*slab_entry, Location);
        NewEntry.*.Next = S.?.FreeList;
        S.?.FreeList = NewEntry;
    }
    return Result;
}

fn SlabAllocMeta(A: ?*slab_allocator) void
{
    var SlabMetaData: slab = undefined;
    SlabInit(A, &SlabMetaData, @sizeOf(slab), true);
    var SlabLoc: usize = undefined;
    var DidAlloc: bool = SlabAlloc(&SlabMetaData, @sizeOf(slab), &SlabLoc);
    std.debug.assert(DidAlloc);

    var NewSlabMeta: ?*slab = @intToPtr(?*slab, SlabLoc);
    NewSlabMeta.?.* = SlabMetaData;
    A.?.MetaSlab = NewSlabMeta;
}

pub export fn SlabAllocatorInit(A: ?*slab_allocator, BackingBuffer: ?[*]u8,
    BackingBufferLength: usize) void
{
    A.?.SlabList = null;
    A.?.Buf = BackingBuffer;
    A.?.BufLen = BackingBufferLength;
    A.?.LeftOffset = 0;
    A.?.RightOffset = BackingBufferLength;
    SlabAllocMeta(A);
}
// TODO(cjb): Don't be stupid, when allocating multiple blocks from a given slab, make sure the
// slabs are contiguous in memory.
pub export fn SlabAllocatorAlloc(A: ?*slab_allocator, RequestedSize: usize) ?*anyopaque {
    var GoodBucketShift: usize = 5;
    while ((RequestedSize > std.math.pow(usize, 2, GoodBucketShift)) and
           (GoodBucketShift < 10))
    {
        GoodBucketShift += 1;
    }

    var BucketSize: usize = std.math.pow(usize, 2, GoodBucketShift);
    var nRequiredSlabAllocs: usize = 1;
    if (RequestedSize > BucketSize)
    {
        nRequiredSlabAllocs = ((RequestedSize / BucketSize) +
                               (RequestedSize & (BucketSize - 1)));
    }
    var BaseLoc: usize = undefined;
    var SlabAllocCount: usize = 0; // This resets if we fail allocation
    while (true)
    {
        var Slab: ?*slab = A.?.SlabList;
        while (Slab != null) : (Slab = Slab.?.NextSlab)
        {
            while (SlabAllocCount < nRequiredSlabAllocs)
            {
                var Tmp: usize = undefined;
                if (SlabAlloc(Slab, BucketSize, &Tmp))
                {
                    // Assert contigous block allocations from baseloc
                    std.debug.assert((SlabAllocCount == 0) or
                                     (Tmp + (1 * BucketSize)) == BaseLoc);
                    BaseLoc = Tmp;
                    if (SlabAllocCount + 1 == nRequiredSlabAllocs)
                    {
                        return @intToPtr(?*anyopaque, BaseLoc);
                    }
                    SlabAllocCount += 1;
                }
                else // Slab allocation fail
                {
                    break;
                }
            }
        }
        var SlabLoc: usize = undefined;
        var DidAlloc: bool = SlabAlloc(A.?.MetaSlab, @sizeOf(slab), &SlabLoc);
        if (!DidAlloc)
        {
            SlabAllocMeta(A);
            _ = SlabAlloc(A.?.MetaSlab, @sizeOf(slab), &SlabLoc);
        }
        var NewSlab: ?*slab = @intToPtr(?*slab, SlabLoc);
        SlabInit(A, NewSlab, BucketSize, false);

        NewSlab.?.NextSlab = A.?.SlabList;
        A.?.SlabList = NewSlab;
    }
}

//pub export fn SlabAllocatorFree(arg_A: [*c]slab_allocator, arg_Ptr: ?*anyopaque) void {
//    var A = arg_A;
//    var Ptr = arg_Ptr;
//    if (!(Ptr != null)) {
//        return;
//    }
//    var Loc: usize = @intCast(usize, @ptrToInt(Ptr));
//    {
//        var Slab: [*c]slab = A.*.SlabList;
//        while (Slab != @ptrCast([*c]slab, @alignCast(@import("std").meta.alignment(slab), @intToPtr(?*anyopaque, @as(c_int, 0))))) : (Slab = Slab.*.NextSlab) {
//            if (SlabFree(Slab, Loc)) {
//                return;
//            }
//        }
//    }
//}

const c = @cImport({
    @cInclude("hs.h");
});

const jpc = extern struct {
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
export fn JPCInit(JPC: ?*jpc, JPCFixedBuffer: ?*anyopaque, JPCFixedBufferSize: usize,
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

export fn JPCExtract(JPC: ?*jpc, Text: ?[*]u8, nTextBytes: c_uint) callconv(.C)
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

export fn JPCDeinit(JPC: ?*jpc) callconv(.C) c_int {
    _ = c.hs_free_scratch(JPC.?.Scratch);

    return JPC_SUCCESS;
}

test "Check hs is working" {}
