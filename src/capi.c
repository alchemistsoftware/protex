#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <assert.h>
#include <hs.h>
#include <sys/mman.h>

typedef struct
{
    hs_database_t *Database;
    hs_scratch_t *Scratch;
} jpc;

int JPCInit(jpc *JPC, char *BackingBuffer, size_t BackingBufferSize, const char *PathZ);
int JPCDeinit(jpc *JPC);
int JPCExtract(jpc *JPC, char *Text, unsigned int nTextBytes);

#define JPC_SUCCESS 0 // Call was executed successfully
#define JPC_INVALID -1 // Bad paramater was passed
#define JPC_UNKNOWN_ERROR -2 // Unhandled internal error

int main()
{
    size_t BackingBufferSize = 1024*1024*8;
    void *BackingBuffer = calloc(1, BackingBufferSize);

    char Text[] = "a quick brown foo";
    jpc JPC = {};
    if (JPCInit(&JPC, BackingBuffer, BackingBufferSize, "./data/db.bin") == JPC_SUCCESS)
    {
        JPCExtract(&JPC,Text, sizeof(Text));
        JPCDeinit(&JPC);
        puts("SUCCESS");
    }
    else
    {
        puts("FAIL");
    }
}
