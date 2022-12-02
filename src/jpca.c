#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <assert.h>
#include <sys/mman.h>

static int PAGE_SIZE = 0;

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

slab *GlobalSlabList;
slab *GlobalSlabMetaData;
uintptr_t GlobalMemStart;

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
static void
SlabInit(slab *S, uintptr_t *SlabStart, unsigned short Size)
{
    /** Map page to "SlabStart" and clear it */
    *SlabStart = (uintptr_t)aligned_alloc(PAGE_SIZE, PAGE_SIZE);
    memset((void *)*SlabStart, 0, PAGE_SIZE);

    S->NextSlab = NULL;
    S->Size = Size;
    S->SlabStart = *SlabStart;

    /** Setup "FreeList" to point to each block */
    unsigned int NumEntries = (PAGE_SIZE / Size) - 1;
    S->FreeList = (slab_entry *)*SlabStart;
    slab_entry *Current = S->FreeList;
    for (unsigned int SlabEntryIndex=1;
         SlabEntryIndex < NumEntries;
         ++SlabEntryIndex)
    {
        Current->Next = (slab_entry *)(*SlabStart + (SlabEntryIndex * Size));
        Current = Current->Next;
    }
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
static bool
SlabAlloc(slab *S, unsigned int Size, uintptr_t *NewLoc)
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
static bool
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
* Allocates and Initializes a "slab of slabs"
*
* - Paramaters:
*   - SlabStart: Location to store new slab
*
* - Returns: Ptr to freshly allocated slab
*/
static slab *
SlabAllocMeta(uintptr_t *SlabStart)
{
    /** Initialize metadata slab */
    slab SlabMetaData;
    SlabInit(&SlabMetaData, SlabStart, sizeof(slab));

    /** Allcoate slot for slab created above */
    uintptr_t SlabLoc;
    bool DidAlloc = SlabAlloc(&SlabMetaData, sizeof(slab), &SlabLoc);
    assert(DidAlloc && (*SlabStart == SlabLoc)); /** Expect first block is used */

    /** Get ptr to slab */
    slab *NewSlabMeta = (slab *)SlabLoc;
    *NewSlabMeta = SlabMetaData;
    return NewSlabMeta;
}

static void
ClearScreen()
{
    printf("\033[H\033[J");
}

static void
CursorToYX(int Y, int X)
{
    printf("\033[%d;%df", (Y), (X));
}

//TODO(cjb):
// - Wrapping
// - Used blocks
// - Slab size
void
DEBUGPrintAllSlabs()//slab *SlabList)
{
    ClearScreen();
    size_t SlabIndex = 0;

    char CharBuffer[128];
    memset(CharBuffer, 0, sizeof(CharBuffer));

    const int SlabBoxHeight = 20;
    const int SlabBoxHorzPad = 10;

    // NOTE(cjb): Cursor row/col pos starts from 1
    const char TopBorderFmtStr[] = "*---Slab: %03d---*"; // TODO(cjb): fmt strs could make 3
                                                         // dynamic....
    int TopBorderCursorXPos = 1;
    int TopBorderCursorYPos = 1;

    const char BottomBorderFmtStr[] = "*---------------*";
    int BottomBorderCursorXPos = 1;
    int BottomBorderCursorYPos = SlabBoxHeight;

    const char RightBorderFmtStr[] = "|";
    int RightBorderCursorXPos = strlen(BottomBorderFmtStr); // TODO(cjb): This changes if bottom
                                                            // needs fmt str
    int RightBorderCursorYPos = 2;

    const char LeftBorderFmtStr[] = "|";
    int LeftBorderCursorXPos = 1;
    int LeftBorderCursorYPos = 2;

    for (slab *Slab = GlobalSlabList;
         Slab != NULL;
         Slab = Slab->NextSlab)
    {
        /** Top Border */
        snprintf(CharBuffer, sizeof(CharBuffer) - 1, TopBorderFmtStr, SlabIndex++); /** Interpret fmt str */
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

        /** Left Border */
        snprintf(CharBuffer, sizeof(CharBuffer) - 1, LeftBorderFmtStr); /** Interpret fmt str */
        for (int CurrentRow=SlabBoxHeight - 1; CurrentRow > 1; --CurrentRow)
        {
            CursorToYX(CurrentRow, LeftBorderCursorXPos); /** Set left border cursor pos */
            printf(CharBuffer); /** Print Left border */
        }
        LeftBorderCursorXPos = TopBorderCursorXPos; /** Update left border x */
        memset(CharBuffer, 0, sizeof(CharBuffer)); /** Clear char buffer */
    }

    printf("\n\n\n\n\n\nEND OF DEBUG OUTPUT\n");
}

// TODO(cjb): jpca struct? housing these 3 ptrs?
// something like slab_allocator_data?
//
// The following functions wrap the slab allocation system

/***
* Initializes Globals: MemStart, SlabList, and MetaDataSlab.
*
* - Paramaters:
*   - MemStart: Initial location of "GlobalMemStart"
*/
void
SlabAllocatorInit(uintptr_t MemStart)
{
    PAGE_SIZE = getpagesize();

    GlobalSlabList = NULL;
    GlobalSlabMetaData = SlabAllocMeta(&MemStart);
    GlobalMemStart = MemStart;
}

/**
*
*/
void *
SlabAllocatorAlloc(size_t Size)
{
    /** Walk slablist for compat block */
    uintptr_t NewLoc;
    slab *Slab = GlobalSlabList;
    for (; Slab; Slab = Slab->NextSlab)
    {
        if (SlabAlloc(Slab, Size, &NewLoc)) /** Found block */
        {
            return (void *)NewLoc;
        }
    }

    /** Allocate new slab */
    uintptr_t SlabLoc;
    bool DidAlloc = SlabAlloc(GlobalSlabMetaData, sizeof(slab), &SlabLoc);
    if (!DidAlloc) /** Allocate new metadata slab */
    {
        GlobalSlabMetaData = SlabAllocMeta(&GlobalMemStart);
        GlobalMemStart += PAGE_SIZE;
        SlabAlloc(GlobalSlabMetaData, sizeof(slab), &SlabLoc);
    }

    /** Initialize new slab */
    slab *NewSlab = (slab *)SlabLoc;
    SlabInit(NewSlab, &GlobalMemStart, Size);
    NewSlab->NextSlab = GlobalSlabList;
    GlobalSlabList = NewSlab;

    /** Allocate block of memory inside new slab */
    SlabAlloc(NewSlab, Size, &NewLoc);
    return (void *)NewLoc;
}

void
SlabAllocatorFree(void *Ptr)
{
    if (!Ptr)
    {
        return;
    }

    uintptr_t Loc = (uintptr_t)Ptr;
    for (slab *Slab = GlobalSlabList;
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
