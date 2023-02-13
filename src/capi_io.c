#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <assert.h>
#include <sys/mman.h>

int ProtexInit(void **ProtexCtx, uint8_t *ArtifactPath);
int ProtexDeinit(void **ProtexCtx);
int ProtexExtract(void **ProtexCtx, uint8_t *Text, uint32_t nTextBytes, uint8_t **Result,
        uint32_t *nBytesCopied);

#define PROTEX_SUCCESS 0 // Call was executed successfully
#define PROTEX_INVALID -1 // Bad paramater was passed
#define PROTEX_UNKNOWN_ERROR -2 // Unhandled internal error

int main(int argc, char **argv)
{
    if (argc < 2)
    {
        fprintf(stdout, "Usage: %s <artifact_path>\n", argv[0]);
        return -1;
    }

    uint8_t Text[1024*5]; // 5kb text buffer for stdin
    uint32_t TextIndex = 0;
    char Ch;
    while(read(STDIN_FILENO, &Ch, 1) > 0)
    {
        Text[TextIndex++] = Ch;
        if (TextIndex >= 1024*5)
        {
            break;
        }
    }

    void *ProtexCtx;
    if (ProtexInit(&ProtexCtx, argv[1]) != PROTEX_SUCCESS)
    {
        puts("ProtexInit failed :(");
        return -1;
    };

    uint8_t *Result;
    uint32_t nBytesCopied;
    if (ProtexExtract(&ProtexCtx, Text, TextIndex, &Result, &nBytesCopied) == PROTEX_SUCCESS)
    {
        for (int CharIndex=0; CharIndex < nBytesCopied; ++CharIndex)
            putchar(Result[CharIndex]);
        putchar('\n');
        ProtexDeinit(&ProtexCtx);
    }
    else
    {
        puts("ProtexExtract failed :(");
        return -1;
    }
}
