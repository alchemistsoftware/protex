//!
//! Slab allocator TODO(cjb): doc
//!

const std = @import("std");

const allocator = std.mem.Allocator;
const self = @This();

// Backing buffer start location
BufferStart: usize,

// Tracks metaslabs advancing 1 page to the right everytime a new slab is required.
LeftOffset: usize,

// Tracks memory allocations advancing 1 page to the left for each new slab.
RightOffset: usize,

// Linked list of slabs ordered left to right
SlabList: ?*slab,

// Slab storing other slabs
MetaSlab: ?*slab,

const slab_block = struct
{
    Next: ?*slab_block,
};

const slab = struct
{
    NextSlab: ?*slab,
    FreeList: ?*slab_block,
    SlabStart: usize,
    Size: u16,
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

fn SlabInitAlign(A: *self, S: ?*slab, Size: u16, Align: usize,
    IsMetaSlab: bool) void
{
    var PageBegin: usize = undefined;
    if (IsMetaSlab)
    {
        // Forward align 'Offset' to the specified alignment
        var CurrentPtr: usize = A.BufferStart + A.*.LeftOffset;
        var Offset: usize = AlignForward(CurrentPtr, Align);
        Offset -= A.BufferStart; // Change to relative offset
        if (Offset + std.mem.page_size <= A.RightOffset)
        {
            PageBegin = A.BufferStart + Offset;
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
        var CurrentPtr: usize = A.BufferStart + A.*.RightOffset;
        var Offset: usize = AlignBackward(CurrentPtr, Align);
        Offset -= A.BufferStart; // Change to relative offset
        if (Offset - std.mem.page_size > A.*.LeftOffset)
        {
            PageBegin = A.BufferStart + Offset - std.mem.page_size;
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
    S.?.FreeList = @intToPtr(?*slab_block, PageBegin + (NumEntries - 1) * Size);
    var Current: ?*slab_block = S.?.FreeList;

    var SlabEntryIndex: isize = @intCast(isize, NumEntries) - 1;
    while (SlabEntryIndex >= 0) : (SlabEntryIndex -= 1)
    {
        Current.?.Next = @intToPtr(?*slab_block, S.?.SlabStart +
                                     @intCast(usize, SlabEntryIndex) * Size);
        Current = Current.?.Next;
    }
}

fn SlabInit(A: *self, S: ?*slab, Size: u16, IsMetaSlab: bool) void {
    return SlabInitAlign(A, S, Size, @sizeOf(?*anyopaque), IsMetaSlab);
}

fn SlabAllocNBlocksForward(S: ?*slab, BlockSize: usize, nRequestedBlocks: usize) bool
{
    var Result: bool = false;
    var FreeBlockCount: usize = 0;
    var CurS: ?*slab = S;
    while ((CurS != null) and
           (CurS.?.Size == BlockSize) and
           (FreeBlockCount < nRequestedBlocks)) : (CurS = CurS.?.NextSlab)
    {
        FreeBlockCount += SlabCountContigFreeBlocks(CurS);
    }
    if (FreeBlockCount >= nRequestedBlocks)
    {
        Result = true;
        CurS = S;
        var AllocCount: usize = 0;
        while (AllocCount < nRequestedBlocks)
        {
            if (CurS.?.FreeList != null)
            {
                AllocCount += 1;
                CurS.?.FreeList = CurS.?.FreeList.?.Next;
                if (AllocCount == (nRequestedBlocks % (std.mem.page_size / BlockSize)))
                {
                    CurS = CurS.?.NextSlab;
                }
            }
            else
            {
                CurS = CurS.?.NextSlab;
            }
        }
    }

    return Result;
}

fn SlabCountContigFreeBlocks(S: ?*slab) usize
{
    var Result: usize = 0;
    const BlockSize = S.?.Size;
    var CurrentBlockPtr = S.?.FreeList;
    var CurrentBlockLoc: usize = 0;
    while(CurrentBlockPtr != null) : (CurrentBlockPtr = CurrentBlockPtr.?.Next)
    {
        const NextBlockLoc = @ptrToInt(CurrentBlockPtr);
        if ((CurrentBlockLoc == 0) or
            (CurrentBlockLoc - BlockSize == NextBlockLoc))
        {
            Result += 1;
        }
        else
        {
            Result = 1;
        }
        CurrentBlockLoc = NextBlockLoc;
    }

    return Result;
}

fn SlabAllocNBlocks(S: ?*slab, BlockSize: usize, BlockCount: *usize, nRequestedBlocks: usize) ?usize
{
    // Base case(s)
    if (S == null)
    {
        return null;
    }
    else if (S.?.Size != BlockSize)
    {
        return SlabAllocNBlocks(S.?.NextSlab, BlockSize, BlockCount, nRequestedBlocks);
    }

    var Result = SlabAllocNBlocks(S.?.NextSlab, BlockSize, BlockCount, nRequestedBlocks);
    var nRemainingBlocks = BlockCount.*;
    BlockCount.* += SlabCountContigFreeBlocks(S);

    if ((Result == null) and
        (BlockCount.* >= nRequestedBlocks))
    {
        const nBlocksFromThisSlab = nRequestedBlocks - nRemainingBlocks;
        if (SlabAllocNBlocksForward(S.?.NextSlab, BlockSize, nRemainingBlocks))
        {
            var BaseLoc: usize = undefined;
            var AllocCount: usize = 0;
            while (AllocCount < nBlocksFromThisSlab) : (AllocCount += 1)
            {
                const DidAquireBlock = SlabAlloc(S, BlockSize, &BaseLoc);
                std.debug.assert(DidAquireBlock);
            }
            Result = BaseLoc;
        }
        else
        {
            // Reset block count to this slab's count since allocation failed
            BlockCount.* -= nRemainingBlocks;
        }
    }

    return Result;
}

fn Alloc(Ctx: *anyopaque, RequestedSize: usize, Log2Align: u8, _: usize) ?[*]u8
{
    const Self = @ptrCast(*self, @alignCast(@alignOf(self), Ctx));
    const PtrAlign = @as(usize, 1) << @intCast(allocator.Log2Align, Log2Align);

    var GoodBucketShift: u8 = 5; // 32
    while ((RequestedSize > std.math.pow(usize, 2, GoodBucketShift)) and
           (GoodBucketShift < 10)) // 1024
    {
        GoodBucketShift += 1;
    }

    var BlockSize: u16 = std.math.pow(u16, 2, GoodBucketShift);

    // TODO(cjb): Better way to do this... see 'jwhear/zig_alt_std/common.zig'
    const BlockCountF = @intToFloat(f32, RequestedSize) / @intToFloat(f32, BlockSize);
    var BlockCount = RequestedSize / BlockSize;
    if (BlockCountF - @intToFloat(f32, BlockCount) > 0)
    {
        BlockCount += 1;
    }
    while (true) // Until allocation is sucessful or out of space
                 // TODO(cjb): not while(true)
    {
        var BlockAccum: usize = 0;
        var BaseLoc: ?usize = SlabAllocNBlocks(Self.*.SlabList, BlockSize, &BlockAccum, BlockCount);
        if (BaseLoc != null)
        {
            return @intToPtr(?[*]u8, BaseLoc.?);
        }

        var SlabLoc: usize = undefined;
        var DidAlloc: bool = SlabAlloc(Self.MetaSlab, @sizeOf(slab), &SlabLoc);
        if (!DidAlloc)
        {
            SlabAllocMeta(Self);
            if (!SlabAlloc(Self.MetaSlab, @sizeOf(slab), &SlabLoc))
            {
                std.debug.print("Failed to alloc metaslab\n", .{}); // FIXME(cjb)
                unreachable;
            }
        }
        var NewSlab: ?*slab = @intToPtr(?*slab, SlabLoc);
        SlabInitAlign(Self, NewSlab, BlockSize, PtrAlign, false);

        NewSlab.?.NextSlab = Self.*.SlabList;
        Self.*.SlabList = NewSlab;
    }
}

//TODO(cjb): Rename me :)
fn SlabAlloc(S: ?*slab, Size: usize, NewLoc: *usize) bool
{
    var Result: bool = true;
    if ((S == null) or
        (S.?.Size != Size) or   // Correct size?
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

fn Free(Ctx: *anyopaque, Buf: []u8, Log2Align: u8, RetAddr: usize) void
{
    _ = Log2Align;
    _ = RetAddr;

    const Self = @ptrCast(*self, @alignCast(@alignOf(self), Ctx));
    const Loc = @ptrToInt(Buf.ptr);
    var S = Self.SlabList;
    while (S != null) : (S = S.?.NextSlab)
    {
        if (SlabFree(S, Loc, Buf.len))
        {
            return;
        }
    }
}

fn SlabFree(S: ?*slab, Location: usize, Size: usize) bool
{
    if ((Location < S.?.SlabStart) or
        (Location >= (S.?.SlabStart + std.mem.page_size)))
    {
        return false;
    }

    // Are at least within the same slab
    const BlockSize = @intCast(usize, S.?.Size);

    // TODO(cjb): Better way to do this...
    const BlockCountF = @intToFloat(f32, Size) / @intToFloat(f32, BlockSize);
    var BlockCount = Size / BlockSize;
    if (BlockCountF - @intToFloat(f32, BlockCount) > 0)
    {
        BlockCount += 1;
    }

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
        const TargetBlockIndex = (BlockLoc - CurrentSlab.?.SlabStart) / BlockSize;
        var NewEntry: *slab_block = @intToPtr(*slab_block,
            CurrentSlab.?.SlabStart + TargetBlockIndex * BlockSize);
        NewEntry.*.Next = CurrentSlab.?.FreeList;
        CurrentSlab.?.FreeList = NewEntry;
    }

    return true;
}

/// Allocate page for new slab which houses the meta slab itself as well as all other slabs.
fn SlabAllocMeta(Self: *self) void
{
    // Initialize slab
    var TmpMetaSlab: slab = undefined;
    SlabInit(Self, &TmpMetaSlab, @sizeOf(slab), true);

    // Allocate space for the metaslab itself
    var BlockLoc: usize = undefined;
    var DidAlloc: bool = SlabAlloc(&TmpMetaSlab, @sizeOf(slab), &BlockLoc);
    std.debug.assert(DidAlloc);

    // Store metaslab in first block of new slab
    var NewMetaSlab = @intToPtr(?*slab, BlockLoc);
    NewMetaSlab.?.* = TmpMetaSlab;

    // Update metaslab ptr
    Self.MetaSlab = NewMetaSlab;
}

fn ClearScreen() void {
    std.debug.print("\x1B[2J", .{});
}
fn MoveCursor(Row: u32, Col: u32) void {
    std.debug.print("\x1B[{};{}H", .{Row, Col});
}
pub fn DEBUGSlabVisularizer(arg_A: *self) void
{
    // TODO(cjb): get stdout writter AND USE IT!!!!
    // ( also refactor this garbage function )

    const ColorRed = "\x1B[0;31m";
    const ColorGreen = "\x1B[0;32m";
    const ColorNormal = "\x1B[0m";

    var A = arg_A;
    ClearScreen();
    var CharBuffer: [128]u8 = undefined;
    for (CharBuffer) |_, Index|
    {
        CharBuffer[Index] = 0;
    }
    const SlabBoxHeight: u32 = 18;
    const SlabBoxHorzPad: u32 = 3;
    const SlabEntryFmtStr = "Block_{0d:0>4}";
    const TopBorderFmtStr = "*-{0d:0>3} {1d:0>4}-*";
    var TopBorderCursorXPos: u32 = 1;
    var TopBorderCursorYPos: u32 = 1;
    const BottomBorderFmtStr = "*----------*";
    var BottomBorderCursorXPos: u32 = 1;
    var BottomBorderCursorYPos: u32 = SlabBoxHeight;
    const RightBorderFmtStr = "|";
    var RightBorderCursorXPos = @intCast(u32, BottomBorderFmtStr.len);
    const LeftBorderFmtStr = "|";
    var LeftBorderCursorXPos: u32= 1;
    var LeftBorderCursorYPos: u32= 2;
    {
        var SlabIndex: usize = 0;
        var Slab: ?*slab = A.*.SlabList;
        while (Slab != null) : (Slab = Slab.?.NextSlab)
        {
            // Top border
            var FmtdCharBufSlice = std.fmt.bufPrint(CharBuffer[0 .. ], TopBorderFmtStr, .{SlabIndex, Slab.?.Size}) catch unreachable;
            MoveCursor(TopBorderCursorYPos, TopBorderCursorXPos);
            std.debug.print("{s}", .{FmtdCharBufSlice});
            TopBorderCursorXPos += @intCast(u32, FmtdCharBufSlice.len) + SlabBoxHorzPad;
            for (CharBuffer) |_, Index|
            {
                CharBuffer[Index] = 0;
            }

            // Right border
            FmtdCharBufSlice = std.fmt.bufPrint(CharBuffer[0 .. ], RightBorderFmtStr, .{}) catch unreachable;
            RightBorderCursorXPos = (TopBorderCursorXPos - SlabBoxHorzPad) - 1;

            {
                var CurrentRow: u32 = SlabBoxHeight - 1;
                while (CurrentRow > 1) : (CurrentRow -= 1)
                {
                    MoveCursor(CurrentRow, RightBorderCursorXPos);
                    std.debug.print("{s}", .{FmtdCharBufSlice});
                }
            }
            for (CharBuffer) |_, Index|
            {
                CharBuffer[Index] = 0;
            }
            FmtdCharBufSlice = std.fmt.bufPrint(CharBuffer[0 .. ], BottomBorderFmtStr, .{}) catch unreachable;
            MoveCursor(BottomBorderCursorYPos, BottomBorderCursorXPos);
            std.debug.print("{s}", .{FmtdCharBufSlice});
            BottomBorderCursorXPos = TopBorderCursorXPos;

            var SlabEntryIndex: usize = 0;
            var NumEntries: usize = std.mem.page_size / Slab.?.Size;
            while (SlabEntryIndex < NumEntries) : (SlabEntryIndex +=1 )
            {
                std.debug.print("{s}", .{ColorRed});
                var CurrentBlock: ?*slab_block = Slab.?.FreeList;
                while(CurrentBlock != null) : (CurrentBlock = CurrentBlock.?.Next)
                {
                    if (@ptrToInt(CurrentBlock) == Slab.?.SlabStart + SlabEntryIndex * Slab.?.Size)
                    {
                        std.debug.print("{s}", .{ColorGreen});
                        break;
                    }
                }
                MoveCursor(LeftBorderCursorYPos + @intCast(u32, SlabEntryIndex), LeftBorderCursorXPos + 1);
                FmtdCharBufSlice = std.fmt.bufPrint(CharBuffer[0 .. ], SlabEntryFmtStr, .{SlabEntryIndex}) catch unreachable;
                std.debug.print("{s}", .{FmtdCharBufSlice});
                for (CharBuffer) |_, Index| CharBuffer[Index] = 0;
            }
            std.debug.print("{s}", .{ColorNormal});

            // Left border
            FmtdCharBufSlice = std.fmt.bufPrint(CharBuffer[0 .. ], LeftBorderFmtStr, .{}) catch unreachable;
            {
                var CurrentRow: u32 = SlabBoxHeight - 1;
                while (CurrentRow > 1) : (CurrentRow -= 1) {
                    MoveCursor(CurrentRow, LeftBorderCursorXPos);
                    std.debug.print("{s}", .{FmtdCharBufSlice});
                }
            }
            LeftBorderCursorXPos = TopBorderCursorXPos;
            for (CharBuffer) |_, Index|
            {
                CharBuffer[Index] = 0;
            }
            SlabIndex += 1;
        }
    }
    MoveCursor(SlabBoxHeight + @as(c_int, 5), @as(c_int, 1)); // MOVE CURSOR SOMEWHERE ELSE!
}

fn Resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_size: usize, ra: usize) bool {
    if (true)
    {
        std.debug.print("Resize hasn't been written yet.... is it time?\n", .{});
        unreachable;
    }

    _ = ctx;
    _ = buf;
    _ = buf_align;
    _ = new_size;
    _ = ra;
    return false;
}

pub fn Init(BackingBuffer: []u8) self
{
    return .{
        .BufferStart = @ptrToInt(BackingBuffer.ptr),
        .LeftOffset = 0,
        .RightOffset = BackingBuffer.len,
        .SlabList = null,
        .MetaSlab = null,
    };
}

pub fn Deinit(Self: *self) void
{
    _ = Self;
}

pub fn Allocator(Self: *self) allocator {
    return allocator{
        .ptr = Self,
        .vtable = &.{
            .alloc = Alloc,
            .resize = Resize,
            .free = Free,
        },
    };
}

test "SlabAllocator"
{
    var Buf: [0x1000*3]u8 = undefined;
    var Slaba = self.Init(Buf[0..]);
    var Ally = self.Allocator(&Slaba);
    var Mem = try Ally.alloc(u8, 512);
    Ally.free(Mem);
    //_ = try Ally.realloc(Mem, 513);
    //DEBUGSlabVisularizer(&Slaba);
}
