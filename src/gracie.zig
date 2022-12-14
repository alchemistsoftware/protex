const std = @import("std");

pub const slab_entry = extern struct
{
    Next: ?*slab_entry,
};

pub const slab = extern struct
{
    NextSlab: ?*slab,
    FreeList: ?*slab_entry,
    SlabStart: usize,
    Size: u16,
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

fn SlabInitAlign(A: *slab_allocator, S: ?*slab, Size: u16, Align: usize,
    IsMetaSlab: bool) void
{
    var PageBegin: usize = undefined;
    if (IsMetaSlab)
    {
        // Forward align 'Offset' to the specified alignment
        var CurrentPtr: usize = @intCast(usize, @ptrToInt(A.*.Buf)) + A.*.LeftOffset;
        var Offset: usize = AlignForward(CurrentPtr, Align);
        Offset -= @intCast(usize, @ptrToInt(A.*.Buf)); // Change to relative offset
        if (Offset + std.mem.page_size <= A.*.RightOffset)
        {
            PageBegin = @intCast(usize, @ptrToInt(A.*.Buf)) + Offset;
            A.*.LeftOffset = Offset + std.mem.page_size;
        }
        else
        {
            std.debug.print("Out of mem\n", .{}); // FIXME(cjb)
            unreachable; // out of mem
        }
    }
    else
    {
        // Backward align 'Offset' to the specified alignment
        var CurrentPtr: usize = @intCast(usize, @ptrToInt(A.*.Buf)) + A.*.RightOffset;
        var Offset: usize = AlignBackward(CurrentPtr, Align);
        Offset -= @intCast(usize, @ptrToInt(A.*.Buf)); // Change to relative offset
        if (Offset - std.mem.page_size > A.*.LeftOffset)
        {
            PageBegin = @intCast(usize, @ptrToInt(A.*.Buf)) + Offset - std.mem.page_size;
            A.*.RightOffset = Offset - std.mem.page_size;
        }
        else
        {
            std.debug.print("Out of mem\n", .{}); // FIXME(cjb)
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

fn SlabInit(A: *slab_allocator, S: ?*slab, Size: u16, IsMetaSlab: bool) void {
    return SlabInitAlign(A, S, Size, @sizeOf(?*anyopaque), IsMetaSlab);
}

fn SlabBlocksBetween(StartBlockLoc: usize, EndBlockLoc: usize, BlockSize: usize) usize
{
    var BlocksBetween: usize = 0;
    var CurrentBlockLoc: usize = EndBlockLoc;
    while(CurrentBlockLoc >= StartBlockLoc) : (BlocksBetween += 1)
    {
        CurrentBlockLoc -= BlockSize;
    }

    return BlocksBetween;
}

/// Choose slab from slablist capable of handling n contigious block allocations.
///
/// Walk slab list performing "dry slaballoc's" to determine if a slab could have handled an
/// allocation. If dry allocation succeded than run checks on that block's position in memory. If
/// The position is ok than increment allocation count, if this is the last required allocation
/// than return the slab in use when allocation count was 0. If the block didn't pass the position
/// checks than the allocation count is reset and the current slab at this point is recorded. Upon
/// dry allocation fail continue to the next slab. Once the slab list is exhausted return null.
///
/// - Paramaters:
///   - S: optional slab ptr to begin search from
///   - Size: block size of the allocation
///   - nBlocks: number of blocks required for this allocation
///
/// - Returns: optional ptr to slab on success otherwise null.
fn FindStartSlabToAllocBlocks(S: ?*slab, Size: usize, nBlocks: usize) ?*slab
{
    var CurrentSlab: ?*slab = S;
    var TargetSlab: ?*slab = CurrentSlab;
    var AllocCount: usize = 0;
    var CurrentBlockLoc: usize = 0;
    while (CurrentSlab != null) : (CurrentSlab = CurrentSlab.?.NextSlab)
    {
        var CurrentBlockPtr = CurrentSlab.?.FreeList;

        // Dry slaballoc
        if ((CurrentSlab.?.Size != Size) or
            (CurrentBlockPtr == null))
        {
            continue;
        }
        while (CurrentBlockPtr != null) : (CurrentBlockPtr = CurrentBlockPtr.?.Next)
        {
            const NextBlockLoc = @intCast(usize, @ptrToInt(CurrentBlockPtr));

            // Verify NextBlockLoc position in memory
            if ((CurrentBlockLoc == 0) or                     // Initial block loc assignment
                (CurrentBlockLoc - Size == NextBlockLoc) or   // Contiguous allocation within slab
                (SlabBlocksBetween(CurrentBlockLoc, NextBlockLoc, Size) <
                 (std.mem.page_size / Size) * 2))             // Next page
            {
                AllocCount += 1;

                if (AllocCount >= nBlocks) // Have enough blocks yet?
                {
                    return TargetSlab;
                }
            }
            else // Failed block position checks... reset and try again.
            {
                AllocCount = 0;
                TargetSlab = CurrentSlab;
            }

            CurrentBlockLoc = NextBlockLoc;
            if (AllocCount == (nBlocks % (std.mem.page_size / Size)))
            {
                break;
            }
        }

    }
    return null;
}

fn SlabAllocNBlocks(S: ?*slab, Size: usize, NewLoc: *usize, nBlocks: usize) bool
{
    var CurrentSlab: ?*slab = FindStartSlabToAllocBlocks(S, Size, nBlocks);
    if (CurrentSlab == null)
    {
        return false;
    }

    var AllocCount: usize = 0;
    while (AllocCount < nBlocks)
    {
        if (CurrentSlab.?.FreeList != null)
        {
            AllocCount += 1;
            if (AllocCount <= (nBlocks % (std.mem.page_size / Size)))
            {
                // Record first block
                if (AllocCount == 1)
                {
                    NewLoc.* = @intCast(usize, @ptrToInt(CurrentSlab.?.FreeList));
                }
            }
            CurrentSlab.?.FreeList = CurrentSlab.?.FreeList.?.Next;
            if (AllocCount == (nBlocks % (std.mem.page_size / Size)))
            {
                CurrentSlab = CurrentSlab.?.NextSlab;
            }
        }
        else
        {
            CurrentSlab = CurrentSlab.?.NextSlab;
        }
    }

    return true;
}


fn SlabAlloc(S: ?*slab, Size: usize, NewLoc: *usize) bool
{
    var Result: bool = true;
    if ((S.?.Size != Size) or   // Correct size?
        (S.?.FreeList == null)) // Is slab full?
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

fn SlabFree(S: ?*slab, Location: usize, Size: usize) bool
{
    var Result: bool = true;
    if ((Location < S.?.SlabStart) or (Location >= (S.?.SlabStart + std.mem.page_size)))
    {
        Result = false;
    }
    else // Are at least within the same slab
    {
        const BlockSize = @intCast(usize, S.?.Size);

        // TODO(cjb): Better way to do this...
        const BlockCountF = @intToFloat(f32, Size) / @intToFloat(f32, BlockSize);
        var BlockCount = Size / BlockSize;
        if (BlockCountF - @intToFloat(f32, BlockCount) > 0)
        {
            BlockCount += 1;
        }

        // Compute starting slab's number of used block's
        const BlocksPerSlab: usize = std.mem.page_size / BlockSize;
        const InitialSlabBlocksUsed = BlocksPerSlab - (Location - S.?.SlabStart) / BlockSize;

        var CurrentSlab = S;
        var nBlocksFreed: usize = 0;
        while(nBlocksFreed < BlockCount) : (nBlocksFreed += 1)
        {
            // Did cross a page boundry?
            const BlockLoc: usize = Location + nBlocksFreed * BlockSize;
            if (BlockLoc >= CurrentSlab.?.SlabStart + std.mem.page_size)
            {
                CurrentSlab = CurrentSlab.?.NextSlab;
                std.debug.assert(CurrentSlab != null);
            }

            // Map nBlocksFreed => TargetBlockIndex
            var TargetBlockIndex: usize = undefined;
            if (nBlocksFreed < InitialSlabBlocksUsed)
            {
                TargetBlockIndex = (BlocksPerSlab - 1) -
                                    (nBlocksFreed % BlocksPerSlab);
            }
            else
            {
                TargetBlockIndex = (BlocksPerSlab - 1) -
                                    ((nBlocksFreed - InitialSlabBlocksUsed) % BlocksPerSlab);
            }

            var NewEntry: *slab_entry = @intToPtr(*slab_entry,
                CurrentSlab.?.SlabStart + TargetBlockIndex * BlockSize);
            NewEntry.*.Next = CurrentSlab.?.FreeList;
            CurrentSlab.?.FreeList = NewEntry;
        }
    }
    return Result;
}

fn SlabAllocMeta(A: *slab_allocator) void
{
    var SlabMetaData: slab = undefined;
    SlabInit(A, &SlabMetaData, @sizeOf(slab), true);
    var SlabLoc: usize = undefined;
    var DidAlloc: bool = SlabAlloc(&SlabMetaData, @sizeOf(slab), &SlabLoc);
    std.debug.assert(DidAlloc);

    var NewSlabMeta: ?*slab = @intToPtr(?*slab, SlabLoc);
    NewSlabMeta.?.* = SlabMetaData;
    A.*.MetaSlab = NewSlabMeta;
}

fn GracieAInit(BackingBuffer: ?[*]u8, BackingBufferLength: usize) slab_allocator
{
    var Allocator: slab_allocator = undefined;
    Allocator.SlabList = null;
    Allocator.Buf = BackingBuffer;
    Allocator.BufLen = BackingBufferLength;
    Allocator.LeftOffset = 0;
    Allocator.RightOffset = BackingBufferLength;
    SlabAllocMeta(&Allocator);

    return Allocator;
}

//pub export fn GracieADeinit() void
//{
//    GSA.SlabList = null;
//    GSA.Buf = null;
//    GSA.BufLen = 0;
//    GSA.LeftOffset = 0;
//    GSA.RightOffset = 0;
//    GSA.MetaSlab = null;
//}

pub export fn GracieAAlloc(A: *slab_allocator, RequestedSize: usize) callconv(.C) ?*anyopaque
{
    var GoodBucketShift: u8 = 5;
    while ((RequestedSize > std.math.pow(usize, 2, GoodBucketShift)) and
           (GoodBucketShift < 10))
    {
        GoodBucketShift += 1;
    }

    var BlockSize: u16 = std.math.pow(u16, 2, GoodBucketShift);

    // TODO(cjb): Better way to do this...
    const BlockCountF = @intToFloat(f32, RequestedSize) / @intToFloat(f32, BlockSize);
    var BlockCount = RequestedSize / BlockSize;
    if (BlockCountF - @intToFloat(f32, BlockCount) > 0)
    {
        BlockCount += 1;
    }
    while (true) // Until allocation is sucessful or out of space
    {
        var BaseLoc: usize = undefined;
        if (SlabAllocNBlocks(A.*.SlabList, BlockSize, &BaseLoc, BlockCount))
        {
            return @intToPtr(?*anyopaque, BaseLoc);
        }

        var SlabLoc: usize = undefined;
        var DidAlloc: bool = SlabAlloc(A.*.MetaSlab, @sizeOf(slab), &SlabLoc);
        if (!DidAlloc)
        {
            SlabAllocMeta(A);
            if (!SlabAlloc(A.*.MetaSlab, @sizeOf(slab), &SlabLoc))
            {
                std.debug.print("Failed to alloc metaslab\n", .{}); // FIXME(cjb)
                unreachable;
            }
        }
        var NewSlab: ?*slab = @intToPtr(?*slab, SlabLoc);
        SlabInit(A, NewSlab, BlockSize, false);

        NewSlab.?.NextSlab = A.*.SlabList;
        A.*.SlabList = NewSlab;
    }
}

fn GracieAFree(A: *slab_allocator, Ptr: ?*anyopaque, Size: usize) void
{
    if (Ptr == null)
    {
        return;
    }
    var Loc: usize = @intCast(usize, @ptrToInt(Ptr));

    var Slab: ?*slab = A.*.SlabList;
    while (Slab != null) : (Slab = Slab.?.NextSlab)
    {
        if (SlabFree(Slab, Loc, Size))
        {
            return;
        }
    }
}

const c = @cImport({
    @cInclude("hs.h");
});

pub const gracie_artifact_header = extern struct {
    SerializedDatabaseSize: usize,
    DeserializedDatabaseSize: usize,
};

pub const gracie = extern struct {
    Database: ?*c.hs_database_t,
    Scratch: ?*c.hs_scratch_t,
    A: slab_allocator,
};

pub const GRACIE_SUCCESS: c_int = 0;        // Call was executed successfully
pub const GRACIE_INVALID: c_int = -1;       // Bad paramater was passed
pub const GRACIE_UNKNOWN_ERROR: c_int = -2; // Unhandled internal error
pub const GRACIE_NOMEM: c_int = -3;         // A memory allocation failed

// TODO(cjb): Integrate this error set into GracieErrhandler.
fn HSLogErrOnFail(HSReturnCode: c_int) !void {
    switch (HSReturnCode) {
        c.HS_SUCCESS => return,
        c.HS_INVALID => std.log.err("HS_INVALID\n", .{}),
        c.HS_NOMEM => std.log.err("HS_NOMEM\n", .{}),
        c.HS_SCAN_TERMINATED => std.log.err("HS_SCAN_TERMINATED\n", .{}),
        c.HS_COMPILER_ERROR => std.log.err("HS_COMPILER_ERROR\n", .{}),
        c.HS_DB_VERSION_ERROR => std.log.err("HS_DB_VERSION_ERROR\n", .{}),
        c.HS_DB_PLATFORM_ERROR => std.log.err("HS_DB_PLATFORM_ERROR\n", .{}),
        c.HS_DB_MODE_ERROR => std.log.err("HS_DB_MODE_ERROR\n", .{}),
        c.HS_BAD_ALIGN => std.log.err("HS_BAD_ALIGN\n", .{}),
        c.HS_BAD_ALLOC => std.log.err("HS_BAD_ALLOC\n", .{}),
        c.HS_SCRATCH_IN_USE => std.log.err("HS_SCRATCH_IN_USE\n", .{}),
        c.HS_ARCH_ERROR => std.log.err("HS_ARCH_ERROR\n", .{}),
        c.HS_INSUFFICIENT_SPACE => std.log.err("HS_INSUFFICIENT_SPACE\n", .{}),
        c.HS_UNKNOWN_ERROR => std.log.err("HS_UNKNOWN_ERROR\n", .{}),
        else => unreachable,
    }
    return error.Error;
}

fn GracieErrHandler(Err: anyerror) c_int
{
    std.log.err("{}", .{Err});
    switch(Err)
    {
        error.OutOfMemory => return GRACIE_NOMEM,
        error.FileNotFound => return GRACIE_INVALID,
        error.Error => return GRACIE_UNKNOWN_ERROR,
        else => unreachable,
    }
}

export fn GracieInit(Gracie: ?*?*gracie, ArtifactPathZ: ?[*:0]const u8) callconv(.C) c_int
{
    // Open artifact file
    var PathLen: usize = 0;
    while (ArtifactPathZ.?[PathLen] != 0) { PathLen += 1; }
    const ArtifactFile = std.fs.cwd().openFile(ArtifactPathZ.?[0..PathLen], .{}) catch |Err|
        return GracieErrHandler(Err);

    // File stat
    const ArtifactStat = ArtifactFile.stat() catch |Err|
        return GracieErrHandler(Err);
    std.debug.assert(ArtifactStat.size > @sizeOf(gracie_artifact_header));

    // Read artifact header
    var ArtifactHeader: gracie_artifact_header = undefined;
    const nHeaderBytesRead = ArtifactFile.read(
        @ptrCast([*]u8, &ArtifactHeader)[0..@sizeOf(gracie_artifact_header)]) catch |Err|
        return GracieErrHandler(Err);
    std.debug.assert(nHeaderBytesRead == @sizeOf(gracie_artifact_header));

    // Setup slab allocator TODO(cjb): Make slab allocator alloc pages
    var BackingBuffer = std.heap.page_allocator.alloc(u8,
        ArtifactHeader.SerializedDatabaseSize + ArtifactHeader.DeserializedDatabaseSize
        + 0x1000*5) catch |Err| return GracieErrHandler(Err);

    var SA: slab_allocator = GracieAInit(BackingBuffer.ptr, BackingBuffer.len);
    Gracie.?.* = @ptrCast(?*gracie, @alignCast(@alignOf(?*gracie),
            GracieAAlloc(&SA, @sizeOf(gracie)).?));
    Gracie.?.*.?.A = SA;

    // Read serialized database
    var SerializedBytes: []u8 = @ptrCast([*]u8,
        GracieAAlloc(&Gracie.?.*.?.A, ArtifactHeader.SerializedDatabaseSize).?)
            [0..ArtifactHeader.SerializedDatabaseSize];
    const nDatabaseBytesRead = ArtifactFile.reader().readAll(SerializedBytes) catch |Err|
        return GracieErrHandler(Err);
    std.debug.assert(nDatabaseBytesRead == ArtifactHeader.SerializedDatabaseSize);
    defer GracieAFree(&Gracie.?.*.?.A, SerializedBytes.ptr, SerializedBytes.len);

    // TODO(cjb): hs_set_misc_allocator()
    Gracie.?.*.?.Database = @ptrCast(*c.hs_database_t,
        GracieAAlloc(&Gracie.?.*.?.A, ArtifactHeader.DeserializedDatabaseSize));
    HSLogErrOnFail(c.hs_deserialize_database_at(
            SerializedBytes.ptr, SerializedBytes.len,
            Gracie.?.*.?.Database)) catch |Err|
        return GracieErrHandler(Err);

    // TODO(cjb): set allocator used for scratch
    Gracie.?.*.?.Scratch = null;
    HSLogErrOnFail(c.hs_alloc_scratch(Gracie.?.*.?.Database, &Gracie.?.*.?.Scratch)) catch |Err|
        return GracieErrHandler(Err);

    return GRACIE_SUCCESS;
}

fn EventHandler(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint,
    Ctx: ?*anyopaque) callconv(.C) c_int
{
    _ = id;
    _ = flags;

    const TextPtr = @ptrCast(?[*]u8, Ctx);
    std.debug.print("Match: '{s}' (from: {d}, to: {d})\n", .{ TextPtr.?[from..to], from, to });
    return 0;
}

export fn GracieExtract(Gracie: ?*?*gracie, Text: ?[*]u8, nTextBytes: c_uint) callconv(.C) c_int
{
    HSLogErrOnFail(c.hs_scan(Gracie.?.*.?.Database, Text, nTextBytes, 0,
            Gracie.?.*.?.Scratch, EventHandler, Text)) catch |Err|
        return GracieErrHandler(Err);

    return GRACIE_SUCCESS;
}

export fn GracieDeinit(Gracie: ?*?*gracie) callconv(.C) c_int {
    _ = c.hs_free_scratch(Gracie.?.*.?.Scratch);
    std.heap.page_allocator.free(Gracie.?.*.?.A.Buf.?[0 .. Gracie.?.*.?.A.BufLen]);

    return GRACIE_SUCCESS;
}

test "Check hs is working" {}