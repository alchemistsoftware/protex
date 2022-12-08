#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <assert.h>
#include <sys/mman.h>

/** SOURCE: http://3zanders.co.uk/2018/02/24/the-slab-allocator/ */

/***
* List of blocks currently free within a slab.
*/
typedef struct slab_entry
{
    struct slab_entry *Next;
} slab_entry;

/***
* Slabs are the amount by which a cache can grow or shrink. It represents a memory allocation to the
* cache from the machine, and it's size is a single page.
*/
typedef struct slab
{
    struct slab *NextSlab; /** Linked list, pointing to other slabs */
    slab_entry *FreeList;  /** Linked list, pointing to free block(s) within the slab */
    uintptr_t SlabStart;   /** Base address of this slab */
    unsigned short Size;   /** Size of objects within a single page */
} slab;

typedef struct
{
    unsigned char *Buf;
    size_t BufLen;
    size_t LeftOffset;
    size_t RightOffset;
    slab *SlabList;
    slab *MetaSlab;
} slab_allocator;

/** https://www.gingerbill.org/article/2019/02/08/memory-allocation-strategies-002/ */

bool
IsPowerOfTwo(uintptr_t x)
{
    return (x & (x - 1)) == 0;
}

uintptr_t
AlignBackward(uintptr_t Ptr, size_t Align)
{
    assert(IsPowerOfTwo(Align) && "Align isn't a power of 2");

    uintptr_t P = Ptr;
    uintptr_t A = (uintptr_t)Align;

    /** Same as (P % A) but faster as 'A' is a power of two */
    uintptr_t Modulo = P & (A - 1);

    if (Modulo != 0)
    {
        P -= Modulo;
    }

    return (P);
}

uintptr_t
AlignForward(uintptr_t Ptr, size_t Align)
{
    assert(IsPowerOfTwo(Align) && "Align isn't a power of 2");

    uintptr_t P = Ptr;
    uintptr_t A = (uintptr_t)Align;

    /** Same as (P % A) but faster as 'A' is a power of two */
    uintptr_t Modulo = P & (A - 1);

    if (Modulo != 0)
    {
        P += A - Modulo;
    }

    return (P);
}

static size_t PAGE_SIZE = 0;

/***
* Initializes a slab, taking a virtual memory location to be managed by this slab as well as the
* size of each object to be allocated. We ask the virtual memory paging system to map a page for
* reading/writing.
*
* - Paramagers:
*   - S: Ptr to slab
*   - SlabStart: Address which the os will map to
*   - Size: Size of objects in this slab
*/
void
SlabInitAlign(slab_allocator *A, slab *S, size_t Size, size_t Align, bool IsMetaSlab)
{
    void *Ptr; // Base slab ptr
    if (IsMetaSlab)
    {
        /** Forward align 'Offset' to the specified alignment */
        uintptr_t CurrentPtr = (uintptr_t)A->Buf + (uintptr_t)A->LeftOffset;
        uintptr_t Offset = AlignForward(CurrentPtr, Align);
        Offset -= (uintptr_t)A->Buf; /** Change to relative offset */

        /** Check to see if the backing memory has space left */
        if (Offset + PAGE_SIZE <= A->RightOffset)
        {
            Ptr = &A->Buf[Offset];
            A->LeftOffset = Offset + PAGE_SIZE;
        }
    }
    else
    {
        /** Backward align 'Offset' to the specified alignment */
        uintptr_t CurrentPtr = (uintptr_t)A->Buf + (uintptr_t)A->RightOffset;
        uintptr_t Offset = AlignBackward(CurrentPtr, Align);
        Offset -= (uintptr_t)A->Buf; /** Change to relative offset */

        /** Check to see if the backing memory has space left */
        if (Offset - PAGE_SIZE > A->LeftOffset)
        {
            Ptr = &A->Buf[Offset - PAGE_SIZE];
            A->RightOffset = Offset - PAGE_SIZE;
        }
    }

    /** Zero out memory by default */
    memset(Ptr, 0, PAGE_SIZE);

    S->NextSlab = NULL;
    S->Size = Size;
    S->SlabStart = (uintptr_t)Ptr;

    /** Setup "FreeList" to point to each block */
    size_t NumEntries = (PAGE_SIZE / Size) - 1;
    S->FreeList = (slab_entry *)Ptr;
    slab_entry *Current = S->FreeList;
    for (unsigned int SlabEntryIndex=1;
         SlabEntryIndex < NumEntries;
         ++SlabEntryIndex)
    {
        Current->Next = (slab_entry *)(S->SlabStart + (SlabEntryIndex * Size));
        Current = Current->Next;
    }
}

#ifndef DEFAULT_ALIGNMENT
#define DEFAULT_ALIGNMENT (2*sizeof(void *))
#endif

void
SlabInit(slab_allocator *A, slab *S, size_t Size, bool IsMetaSlab)
{
   return SlabInitAlign(A, S, Size, DEFAULT_ALIGNMENT, IsMetaSlab);
}

/***
* Takes virtual memory location which will be asked to be managed by this slab and the size of each
* object we'll be allocating. The alloc function pops a free object off the list The alloc function
* pops a free object off the list.
*
* - Paramaters:
*   - S: Ptr to slab
*   - Size: Size of object to be allocated
*   - NewLoc: Address to be managed by this slab
*
* - Returns: true upon success, false otherwise
*/
bool
SlabAlloc(slab *S, size_t Size, uintptr_t *NewLoc)
{
    bool Result = true;

    /** Check requested size matches Slab's size & there are blocks avaliable */
    if (S->Size != Size || S->FreeList == NULL)
    {
        Result = false;
    }
    else /** Pop block from "FreeList" and write "NewLoc" */
    {
        *NewLoc = (uintptr_t)S->FreeList;
        S->FreeList = S->FreeList->Next;
    }
    return (Result);
}

/***
* Adds object back to free list, after checking that the memory location being freed is within the
* slab.
*
* - Paramaters:
*   - S: Slab ptr
*   - Location: Address of the object to be free'd
*
* - Returns: true upon success, false otherwise
*/
bool
SlabFree(slab *S, uintptr_t Location)
{
    bool Result = true;

    // TODO(cjb): Other checks, such as Location being a multiple of Size
    /** Check if this address is within slab */
    if (Location < S->SlabStart || Location >= S->SlabStart + PAGE_SIZE)
    {
        Result = false;
    }
    else /** Update "FreeList" head to point to Free'd block */
    {
        slab_entry *NewEntry = (slab_entry *)Location;
        NewEntry->Next = S->FreeList;
        S->FreeList = NewEntry;
    }
    return (Result);
}

/***
* Allocates and Initializes "slab of slabs"
*
* - Paramaters:
*   - SlabStart: Location to store new slab
*
* - Returns: Ptr to freshly allocated slab
*/
void // TODO(cjb): make this return bool
SlabAllocMeta(slab_allocator *A)//uintptr_t *SlabStart)
{
    /** Initialize metadata slab */
    slab SlabMetaData;
    SlabInit(A, &SlabMetaData, sizeof(slab), true);

    /** Allcoate slot for slab created above */
    uintptr_t SlabLoc;
    bool DidAlloc = SlabAlloc(&SlabMetaData, sizeof(slab), &SlabLoc);
    assert(DidAlloc && "Failed to allocate MetaSlab");

    /** Get ptr to slab and copy it to MetaSlab */
    slab *NewSlabMeta = (slab *)SlabLoc;
    *NewSlabMeta = SlabMetaData;
    A->MetaSlab = NewSlabMeta;
}

void
ClearScreen()
{
    printf("\033[H\033[J");
}

void
CursorToYX(int Y, int X)
{
    printf("\033[%d;%df", (Y), (X));
}

//TODO(cjb):
// - Wrapping
// - Used blocks
// - Slab size
void
DEBUGPrintAllSlabs(slab_allocator *A)
{
    ClearScreen();
    size_t SlabIndex = 0;

    char CharBuffer[128];
    memset(CharBuffer, 0, sizeof(CharBuffer));

    const int SlabBoxHeight = 17;
    const int SlabBoxHorzPad = 4;

    const char SlabEntryFmtStr[] = "%x";

    // NOTE(cjb): Cursor row/col pos starts from 1
    const char TopBorderFmtStr[] = "*-%03d %03d-*"; // TODO(cjb): fmt strs could make 3
                                                         // dynamic....
    int TopBorderCursorXPos = 1;
    int TopBorderCursorYPos = 1;

    const char BottomBorderFmtStr[] = "*---------*";
    int BottomBorderCursorXPos = 1;
    int BottomBorderCursorYPos = SlabBoxHeight;

    const char RightBorderFmtStr[] = "|";
    int RightBorderCursorXPos = strlen(BottomBorderFmtStr); // TODO(cjb): This changes if bottom
                                                            // needs fmt str
    int RightBorderCursorYPos = 2;

    const char LeftBorderFmtStr[] = "|";
    int LeftBorderCursorXPos = 1;
    int LeftBorderCursorYPos = 2;

    for (slab *Slab = A->SlabList;
         Slab != NULL;
         Slab = Slab->NextSlab)
    {
        /** Top Border */
        snprintf(CharBuffer, sizeof(CharBuffer) - 1, TopBorderFmtStr,
                SlabIndex, Slab->Size); /** Interpret fmt str */
        CursorToYX(TopBorderCursorYPos, TopBorderCursorXPos); /** Set top border cursor pos */
        printf(CharBuffer); /** Print Top border */
        TopBorderCursorXPos += strlen(CharBuffer)
                              + SlabBoxHorzPad; /** Update top border x */
        memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */

        /** Right Border */
        snprintf(CharBuffer, sizeof(CharBuffer - 1), RightBorderFmtStr); /** Interpret fmt str */
        RightBorderCursorXPos = TopBorderCursorXPos - SlabBoxHorzPad - 1; /** Update right border x */
        for (int CurrentRow=SlabBoxHeight - 1; CurrentRow > 1; --CurrentRow)
        {
            CursorToYX(CurrentRow, RightBorderCursorXPos); /** Set right border cursor pos */
            printf(CharBuffer); /** Print Right border */
        }
        memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */

        /** Bottom Border */
        snprintf(CharBuffer, sizeof(CharBuffer) - 1, BottomBorderFmtStr); /** Interpret fmt str */
        CursorToYX(BottomBorderCursorYPos,
                BottomBorderCursorXPos); /** Set bottom border cursor pos */
        printf(CharBuffer); /** Print Bottom border */
        BottomBorderCursorXPos = TopBorderCursorXPos; /** Update bottom border x */
        memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */

        /** Slab Entries */
        size_t NumEntries = (PAGE_SIZE / Slab->Size) - 1;
        slab_entry *Current = (slab_entry *)Slab->SlabStart;
        size_t SlabEntryIndex = 0;
        while (Current != NULL)
        {
            if ((SlabEntryIndex + LeftBorderCursorYPos >= SlabBoxHeight - 2))
            {
                int SlabsBetween = NumEntries - SlabEntryIndex - 2;
                CursorToYX(LeftBorderCursorYPos + SlabEntryIndex,
                        LeftBorderCursorXPos + 2); /** Set border cursor pos to entry */
                snprintf(CharBuffer, sizeof(CharBuffer) - 1,
                    "..%03d..", SlabsBetween); /** Interpret fmt str */
                printf(CharBuffer); /** Print address */
                memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */

                slab_entry *LastSlab = (slab_entry *)((uintptr_t)Current + (Slab->Size *
                            (SlabsBetween)));
                CursorToYX(LeftBorderCursorYPos + 1 + SlabEntryIndex,
                        LeftBorderCursorXPos + 1); /** Set border cursor pos to entry */
                snprintf(CharBuffer, sizeof(CharBuffer) - 1,
                        SlabEntryFmtStr, LastSlab); /** Interpret fmt str */
                printf(CharBuffer); /** Print address */
                memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */

                break;
            }

            CursorToYX(LeftBorderCursorYPos + SlabEntryIndex,
                    LeftBorderCursorXPos + 1); /** Set border cursor pos to entry */
            snprintf(CharBuffer, sizeof(CharBuffer) - 1,
                    SlabEntryFmtStr, Current); /** Interpret fmt str */
            printf(CharBuffer); /** Print address */
            memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */

            // Don't advance if this is the last entry
            if (SlabEntryIndex == NumEntries)
            {
                break;
            }
            Current = Current->Next;
            SlabEntryIndex += 1;
        }

        /** Left Border */
        snprintf(CharBuffer, sizeof(CharBuffer) - 1, LeftBorderFmtStr); /** Interpret fmt str */
        for (int CurrentRow=SlabBoxHeight - 1; CurrentRow > 1; --CurrentRow)
        {
            CursorToYX(CurrentRow, LeftBorderCursorXPos); /** Set left border cursor pos */
            printf(CharBuffer); /** Print Left border */
        }
        LeftBorderCursorXPos = TopBorderCursorXPos; /** Update left border x */
        memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */

        SlabIndex += 1;
    }

    CursorToYX(SlabBoxHeight + 5, 1);
    printf("END OF DEBUG OUTPUT\n");
}

// The following functions wrap the slab allocation system

/***
* Initializes Globals: MemStart, SlabList, and MetaDataSlab.
*
* - Paramaters:
*   - MemStart: Initial location of "GlobalMemStart"
*/
void
SlabAllocatorInit(slab_allocator *A, unsigned char *BackingBuffer, size_t BackingBufferLength)
{
    PAGE_SIZE = getpagesize();

    A->SlabList = NULL;
    A->Buf = BackingBuffer;
    A->BufLen = BackingBufferLength;
    A->LeftOffset = 0;
    A->RightOffset = BackingBufferLength;
    SlabAllocMeta(A);
}

#ifndef INITIAL_BUCKET_SHIFT
#define INITIAL_BUCKET_SHIFT 5
#endif

#ifndef MAX_BUCKET_SHIFT
#define MAX_BUCKET_SHIFT 10
#endif

void *
SlabAllocatorAlloc(slab_allocator *A, size_t RequestedSize)
{
    /** Figure out "good" bucket size i.e. nice reusable power of 2 */
    size_t GoodBucketShift = INITIAL_BUCKET_SHIFT;
    while ((RequestedSize > (1 << GoodBucketShift)) &&
           (GoodBucketShift < MAX_BUCKET_SHIFT))
    {
        GoodBucketShift += 1;
    }
    size_t BucketSize = (1 << GoodBucketShift);
    size_t nRequiredSlabAllocs = 1;

    /** If requested size is still larger than the bucket size; will require multi slab block
      allocations */
    if (RequestedSize > BucketSize)
    {
        nRequiredSlabAllocs = ((RequestedSize / BucketSize) +
                               (RequestedSize & (BucketSize - 1)));
    }

    size_t SlabAllocCount=0;
    uintptr_t BaseLoc;
    while(1)
    {
        /** Walk slablist for compat block */
        slab *Slab = A->SlabList;
        for (; Slab; Slab = Slab->NextSlab)
        {
            while (SlabAllocCount < nRequiredSlabAllocs)
            {
                uintptr_t Tmp;
                if (SlabAlloc(Slab, BucketSize, &Tmp)) /** Found block */
                {
                    if (SlabAllocCount == 0) /** Store addr of first block */
                    {
                        BaseLoc = Tmp;
                    }
                    if (SlabAllocCount + 1 == nRequiredSlabAllocs)
                    {
                        return (void *)BaseLoc;
                    }
                    SlabAllocCount += 1;
                }
                else
                {
                    break;
                }
            }
        }

        /** Try and pop a metadata slab */
        uintptr_t SlabLoc;
        bool DidAlloc = SlabAlloc(A->MetaSlab, sizeof(slab), &SlabLoc);
        if (!DidAlloc) /** Need more metadata space */
        {
            SlabAllocMeta(A);
            SlabAlloc(A->MetaSlab, sizeof(slab), &SlabLoc);
        }

        /** Initialize slab */
        slab *NewSlab = (slab *)SlabLoc;
        SlabInit(A, NewSlab, BucketSize, false);

        /** Update slab list */
        NewSlab->NextSlab = A->SlabList;
        A->SlabList = NewSlab;
    }
    assert(0 && "Invalid code path");
}

void
SlabAllocatorFree(slab_allocator *A, void *Ptr)
{
    if (!Ptr)
    {
        return;
    }

    uintptr_t Loc = (uintptr_t)Ptr;
    for (slab *Slab = A->SlabList;
         Slab != NULL;
         Slab = Slab->NextSlab)
    {
        if (SlabFree(Slab, Loc))
        {
            return;
        }
    }

    /** UNREACHABLE */
}
