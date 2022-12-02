#include "jpca.c"

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
    //TODO(cjb): Fixed sized slab blks
    //TODO(cjb): Multipage allocations
    //void *EntirePagePlus1 = SlabAllocatorAlloc(0x1001); // Expected allocation is 2 pages...
    SlabAllocatorInit(0);
    void *_01alloc = SlabAllocatorAlloc(36);
    void *_02alloc = SlabAllocatorAlloc(35); // force diffrent slab
    DEBUGPrintAllSlabs();

    char Text[] = "a quick brown foo";
    job_posting_classifier JPC = {};

    void *Mem = calloc(1, 1024*10);
    if (JPCInit(&JPC, Mem, 1024*10,"./data/db.bin") == JPC_SUCCESS)
    {
        JPCExtract(&JPC,Text, sizeof(Text));
        JPCDeinit(&JPC);
        puts("OK");
    }
    else
    {
        puts("FAIL");
    }
    while(1) {}
}
