#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <assert.h>
#include <hs.h>
#include <sys/mman.h>

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

void SlabAllocatorInit(slab_allocator *A, unsigned char *BackingBuffer, size_t BackingBufferLength);
void *SlabAllocatorAlloc(slab_allocator *A, size_t RequestedSize);
void SlabAllocatorFree(slab_allocator *A, void *Ptr);

typedef struct
{
    void *(*Alloc) (slab_allocator *A, size_t Size);
} jpc_allocfn;

typedef struct
{
    void *(*Free) (slab_allocator *A, void *Ptr);
} jpc_freefn;

typedef struct
{
    jpc_allocfn AllocFn;
    jpc_freefn FreeFn;
} jpc_allocator;

typedef struct
{
    hs_database_t *Database;
    hs_scratch_t *Scratch;
} jpc;

int JPCInit(job_posting_classifier *JPC, void *Mem, size_t Size, const char *PathZ);
int JPCDeinit(job_posting_classifier *JPC);
int JPCExtract(job_posting_classifier *JPC, char *Text, unsigned int nTextBytes);


#define JPC_SUCCESS 0 // Call was executed successfully
#define JPC_INVALID -1 // Bad paramater was passed
#define JPC_UNKNOWN_ERROR -2 // Unhandled internal error

int main()
{
    slab_allocator A;
    size_t BackingBufferSize = 1024*1024*8;
    void *BackingBuffer = calloc(1, BackingBufferSize);
    SlabAllocatorInit(&A, BackingBuffer, BackingBufferSize);
    char *JPCScratch = (char *)SlabAllocatorAlloc(&A, 1024*1024*7);
    printf("Alloc Addr: %x\n", JPCScratch);
    slab *Slab = A.SlabList;
    while (Slab != NULL)
    {
        printf("%x:%d -> %x\n", Slab, Slab->Size, Slab->SlabStart);
        Slab = Slab->NextSlab;
    }

    //char Text[] = "a quick brown foo";
    //job_posting_classifier JPC = {};
    //if (JPCInit(&JPC, "./data/db.bin") == JPC_SUCCESS)
    //{
    //    JPCExtract(&JPC,Text, sizeof(Text));
    //    JPCDeinit(&JPC);
    //    puts("SUCCESS");
    //}
    //else
    //{
    //    puts("FAIL");
    //}

//    SlabAllocatorFree(&A, JPCScratch);
}
