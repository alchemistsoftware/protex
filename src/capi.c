#include "stdio.h"
#include "string.h"
#include "/usr/local/include/hs/hs.h"

typedef struct {
    hs_database_t *Database;
    hs_scratch_t *Scratch;
} job_posting_classifier;

int JPCInitialize(job_posting_classifier *JPC, const char *PathZ);
int JPCExtract(job_posting_classifier *JPC, char *Text, unsigned int nTextBytes);

int main()
{
    job_posting_classifier JPC = {};
    if (JPCInitialize(&JPC, "./data/db.bin") == 0)
    {
        JPCExtract(&JPC, "foo", 3);
        puts("OK");
    }
    else
    {
        puts("FAIL");
    }

}
