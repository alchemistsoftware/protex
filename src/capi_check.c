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
} gracie;

int GracieInit(void **GracieCtx, char *ArtifactPath);
int GracieDeinit(void **GracieCtx);
int GracieExtract(void **GracieCtx, char *Text, unsigned int nTextBytes);

#define GRACIE_SUCCESS 0 // Call was executed successfully
#define GRACIE_INVALID -1 // Bad paramater was passed
#define GRACIE_UNKNOWN_ERROR -2 // Unhandled internal error

int main()
{
    void *GracieCtx;
    if (GracieInit(&GracieCtx, "./data/gracie.bin") != GRACIE_SUCCESS)
    {
        puts("GracieInit failed :(");
        return -1;
    };

    char Text[] = "a foo quick brown foo";
    if (GracieExtract(&GracieCtx, Text, sizeof(Text)) == GRACIE_SUCCESS)
    {
        GracieDeinit(&GracieCtx);
    }
    else
    {
        puts("GracieExtract failed :(");
        return -1;
    }

    puts("OK");
}
