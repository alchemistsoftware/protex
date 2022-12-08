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

pub var PAGE_SIZE: usize = 0;

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
        if (Offset + PAGE_SIZE <= A.?.RightOffset)
        {
            PageBegin = @intCast(usize, @ptrToInt(A.?.Buf)) + Offset;
            A.?.LeftOffset = Offset + PAGE_SIZE;
        }
    }
    else
    {
        // Backward align 'Offset' to the specified alignment
        var CurrentPtr: usize = @intCast(usize, @ptrToInt(A.?.Buf)) + A.?.RightOffset;
        var Offset: usize = AlignBackward(CurrentPtr, Align);
        Offset -= @intCast(usize, @ptrToInt(A.?.Buf)); // Change to relative offset
        if (Offset - PAGE_SIZE > A.?.LeftOffset)
        {
            PageBegin = @intCast(usize, @ptrToInt(A.?.Buf)) + Offset - PAGE_SIZE;
            A.?.RightOffset = Offset - PAGE_SIZE;
        }
    }

    for (@intToPtr([*]u8, PageBegin)[0..PAGE_SIZE]) |*Byte| Byte.* = 0;

    S.?.NextSlab = null;
    S.?.Size = Size;
    S.?.SlabStart = PageBegin;

    // TODO(cjb): Assert PAGE_SIZE divides Size evenly
    var NumEntries: usize = (PAGE_SIZE / Size);
    S.?.FreeList = @intToPtr(?*slab_entry, PageBegin); //@ptrCast(?*slab_entry, @alignCast(@alignOf(slab_entry), Ptr));
    var Current: ?*slab_entry = S.?.FreeList;

    var SlabEntryIndex: usize = 1;
    while (SlabEntryIndex < NumEntries) : (SlabEntryIndex += 1)
    {
        Current.?.Next = @intToPtr(?*slab_entry, S.?.SlabStart + SlabEntryIndex * Size);
        Current = Current.?.Next;
    }
}

pub export fn SlabInit(A: ?*slab_allocator, S: ?*slab, Size: usize, IsMetaSlab: bool) void {
    return SlabInitAlign(A, S, Size, 2*@sizeOf(?*anyopaque), IsMetaSlab);
}

//pub export fn SlabAlloc(S: ?*slab, Size: usize, NewLoc: *usize) bool
//{
//    var Result: bool = true;
//    if ((@bitCast(c_ulong, @as(c_ulong, S.*.Size)) != Size) or (S.*.FreeList == @ptrCast([*c]slab_entry, @alignCast(@import("std").meta.alignment(slab_entry), @intToPtr(?*anyopaque, @as(c_int, 0)))))) {
//        Result = @as(c_int, 0) != 0;
//    }
//    else
//    {
//        NewLoc.* = @intCast(usize, @ptrToInt(S.*.FreeList));
//        S.*.FreeList = S.*.FreeList.*.Next;
//    }
//    return (Result);
//}

//pub export fn SlabFree(arg_S: [*c]slab, arg_Location: usize) bool {
//    var S = arg_S;
//    var Location = arg_Location;
//    var Result: bool = @as(c_int, 1) != 0;
//    if ((Location < S.*.SlabStart) or (Location >= (S.*.SlabStart +% PAGE_SIZE))) {
//        Result = @as(c_int, 0) != 0;
//    } else {
//        var NewEntry: [*c]slab_entry = @intToPtr([*c]slab_entry, Location);
//        NewEntry.*.Next = S.*.FreeList;
//        S.*.FreeList = NewEntry;
//    }
//    return Result;
//}
//pub export fn SlabAllocMeta(arg_A: [*c]slab_allocator) void {
//    var A = arg_A;
//    var SlabMetaData: slab = undefined;
//    SlabInit(A, &SlabMetaData, @sizeOf(slab), @as(c_int, 1) != 0);
//    var SlabLoc: usize = undefined;
//    var DidAlloc: bool = SlabAlloc(&SlabMetaData, @sizeOf(slab), &SlabLoc);
//    _ = blk: {
//        _ = @sizeOf(c_int);
//        break :blk blk_1: {
//            break :blk_1 if ((@as(c_int, @boolToInt(DidAlloc)) != 0) and ("Failed to allocate MetaSlab" != null)) {} else {
//                __assert_fail("DidAlloc && \"Failed to allocate MetaSlab\"", "src/slab_allocator.c", @bitCast(c_uint, @as(c_int, 241)), "void SlabAllocMeta(slab_allocator *)");
//            };
//        };
//    };
//    var NewSlabMeta: [*c]slab = @intToPtr([*c]slab, SlabLoc);
//    NewSlabMeta.* = SlabMetaData;
//    A.*.MetaSlab = NewSlabMeta;
//}
//pub export fn ClearScreen() void {
//    _ = printf("\x1b[H\x1b[J");
//}
//pub export fn CursorToYX(arg_Y: c_int, arg_X: c_int) void {
//    var Y = arg_Y;
//    var X = arg_X;
//    _ = printf("\x1b[%d;%df", Y, X);
//}
//pub export fn SlabAllocatorInit(arg_A: [*c]slab_allocator, arg_BackingBuffer: [*c]u8, arg_BackingBufferLength: usize) void {
//    var A = arg_A;
//    var BackingBuffer = arg_BackingBuffer;
//    var BackingBufferLength = arg_BackingBufferLength;
//    PAGE_SIZE = @bitCast(usize, @as(c_long, getpagesize()));
//    A.*.SlabList = null;
//    A.*.Buf = BackingBuffer;
//    A.*.BufLen = BackingBufferLength;
//    A.*.LeftOffset = 0;
//    A.*.RightOffset = BackingBufferLength;
//    SlabAllocMeta(A);
//}
//pub export fn SlabAllocatorAlloc(arg_A: [*c]slab_allocator, arg_RequestedSize: usize) ?*anyopaque {
//    var A = arg_A;
//    var RequestedSize = arg_RequestedSize;
//    var GoodBucketShift: usize = 5;
//    while ((RequestedSize > @bitCast(c_ulong, @as(c_long, @as(c_int, 1) << @intCast(@import("std").math.Log2Int(c_int), GoodBucketShift)))) and (GoodBucketShift < @bitCast(c_ulong, @as(c_long, @as(c_int, 10))))) {
//        GoodBucketShift +%= @bitCast(c_ulong, @as(c_long, @as(c_int, 1)));
//    }
//    var BucketSize: usize = @bitCast(usize, @as(c_long, @as(c_int, 1) << @intCast(@import("std").math.Log2Int(c_int), GoodBucketShift)));
//    var nRequiredSlabAllocs: usize = 1;
//    if (RequestedSize > BucketSize) {
//        nRequiredSlabAllocs = (RequestedSize / BucketSize) +% (RequestedSize & (BucketSize -% @bitCast(c_ulong, @as(c_long, @as(c_int, 1)))));
//    }
//    var SlabAllocCount: usize = 0;
//    var BaseLoc: usize = undefined;
//    while (true) {
//        var Slab: [*c]slab = A.*.SlabList;
//        while (Slab != null) : (Slab = Slab.*.NextSlab) {
//            while (SlabAllocCount < nRequiredSlabAllocs) {
//                var Tmp: usize = undefined;
//                if (SlabAlloc(Slab, BucketSize, &Tmp)) {
//                    if (SlabAllocCount == @bitCast(c_ulong, @as(c_long, @as(c_int, 0)))) {
//                        BaseLoc = Tmp;
//                    }
//                    if ((SlabAllocCount +% @bitCast(c_ulong, @as(c_long, @as(c_int, 1)))) == nRequiredSlabAllocs) {
//                        return @intToPtr(?*anyopaque, BaseLoc);
//                    }
//                    SlabAllocCount +%= @bitCast(c_ulong, @as(c_long, @as(c_int, 1)));
//                } else {
//                    break;
//                }
//            }
//        }
//        var SlabLoc: usize = undefined;
//        var DidAlloc: bool = SlabAlloc(A.*.MetaSlab, @sizeOf(slab), &SlabLoc);
//        if (!DidAlloc) {
//            SlabAllocMeta(A);
//            _ = SlabAlloc(A.*.MetaSlab, @sizeOf(slab), &SlabLoc);
//        }
//        var NewSlab: [*c]slab = @intToPtr([*c]slab, SlabLoc);
//        SlabInit(A, NewSlab, BucketSize, @as(c_int, 0) != 0);
//        NewSlab.*.NextSlab = A.*.SlabList;
//        A.*.SlabList = NewSlab;
//    }
//    _ = blk: {
//        _ = @sizeOf(c_int);
//        break :blk blk_1: {
//            break :blk_1 if (false and ("Invalid code path" != null)) {} else {
//                __assert_fail("0 && \"Invalid code path\"", "src/slab_allocator.c", @bitCast(c_uint, @as(c_int, 487)), "void *SlabAllocatorAlloc(slab_allocator *, size_t)");
//            };
//        };
//    };
//    return null;
//}
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
