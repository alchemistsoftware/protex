#include "stdio.h"
#include "string.h"
#include "hs.h"

typedef struct {
    hs_database_t *Database;
    hs_scratch_t *Scratch;
} job_posting_classifier;

int JPCInit(job_posting_classifier *JPC, const char *PathZ);
int JPCDeinit(job_posting_classifier *JPC);
int JPCExtract(job_posting_classifier *JPC, char *Text, unsigned int nTextBytes);

#define JPC_SUCCESS 0 // Call was executed successfully
#define JPC_INVALID -1 // Bad paramater was passed
#define JPC_UNKNOWN_ERROR -2 // Unhandled internal error

int main()
{
    char Text[] = "a quick brown foo";
    job_posting_classifier JPC = {};

    JPCInit

    if (JPCInit(&JPC, "./data/db.bin") == JPC_SUCCESS)
    {
        JPCExtract(&JPC,Text, sizeof(Text));
        JPCDeinit(&JPC);
        puts("OK");
    }
    else
    {
        puts("FAIL");
    }
}
