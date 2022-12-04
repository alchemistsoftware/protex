#include "slab_allocator.c"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <assert.h>
#include <hs.h>
#include <sys/mman.h>

typedef struct {
    hs_database_t *Database;
    hs_scratch_t *Scratch;
} job_posting_classifier;

int JPCInit(job_posting_classifier *JPC, void *Mem, size_t Size, const char *PathZ);
int JPCDeinit(job_posting_classifier *JPC);
int JPCExtract(job_posting_classifier *JPC, char *Text, unsigned int nTextBytes);

#define JPC_SUCCESS 0 // Call was executed successfully
#define JPC_INVALID -1 // Bad paramater was passed
#define JPC_UNKNOWN_ERROR -2 // Unhandled internal error

int main()
{
    //slab_allocator A;
    //size_t BackingBufferSize = 1024*1024*8; // 8mb
    //void *BackingBuffer = calloc(1, BackingBufferSize);
    //SlabAllocatorInit(&A, BackingBuffer, BackingBufferSize);
    //void *JPCScratch = SlabAllocatorAlloc(&A, JPCScratchSize);
    //DEBUGPrintAllSlabs(&A);

    size_t JPCFixedBufferSize = 1024*1024*8;
    void *JPCFixedBuffer = calloc(1, JPCFixedBufferSize);
    char Text[] = "a quick brown foo";
    job_posting_classifier JPC = {};
    if (JPCInit(&JPC, JPCFixedBuffer, JPCFixedBufferSize, "./data/db.bin") == JPC_SUCCESS)
    {
        JPCExtract(&JPC,Text, sizeof(Text));
        JPCDeinit(&JPC);
        puts("SUCCESS");
    }
    else
    {
        puts("FAIL");
    }

    free(JPCFixedBuffer);

}
