#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <assert.h>
#include <sys/mman.h>

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

    char Text[] = "Prep Cooks/Cooks Starting at $25 an Hour Qualifications\n\
\n\
    Restaurant: 1 year (Required)\n\
\n\
    Work authorization (Required)\n\
\n\
    High school or equivalent (Preferred)\n\
\n\
Benefits\n\
Pulled from the full job description\n\
Employee discount\n\
Paid time off\n\
Full Job Description\n\
\n\
Cooks\n\
\n\
Great Opportunity to work at a new all-seasons resort in Northern Catskills - Wylder Windham Hotel.\n\
\n\
We are looking for a dedicated, passionate, and skilled person to become a part of our pre-opening kitchen team for our Babbler's Restaurant. Our four-season resort will offer 110 hotel rooms, 1 restaurant, 1 Bakery with 20 acres of land alongside the Batavia Kill River, our family-friendly, all-season resort is filled with endless opportunities. This newly reimagined property offers banquet, wedding, and event facilities. We are looking for someone who is both willing to roll up their sleeves and work hard and has a desire to produce a first-class experience for our guests. Looking for applicants who are positive, upbeat, team-oriented, and a people person.\n\
\n\
Wylder is an ever growing hotel brand with locations in Lake Tahoe, California and Tilghman Maryland.\n\
\n\
Lots of room for upward growth within the company at the Wylder Windham property and Beyond.\n\
\n\
Young at heart, active, ambitious individuals encouraged to apply!\n\
\n\
Must work weekends, nights, holidays and be flexible with schedule. Must be able to lift 50 pounds and work a physical Labor Job.\n\
\n\
Wylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family-friendly in all aspects!.\n\
\n\
Wylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family friendly in all aspects!\n\
\n\
Competitive Pay- starting at $25-$26+ per hour based on experience\n\
\n\
Job Type: Full-time/Part-Time\n\
\n\
Job Type: Full-time\n\
\n\
Pay: From $25-$26+ per hour based on experience\n\
\n\
Benefits:\n\
\n\
    Employee discount\n\
    Paid time off\n\
\n\
Schedule:\n\
\n\
    10 hour shift\n\
    8 hour shift\n\
    Every weekend\n\
    Holidays\n\
    Monday to Friday\n\
    Weekend availability\n\
\n\
Education:\n\
\n\
    High school or equivalent (Preferred)\n\
\n\
Experience:\n\
\n\
    cooking: 1 year (Preferred)\n\
\n\
Work Location: One location\n\
\n\
Job Type: Full-time\n\
\n\
Pay: $25.00 - $26.00 per hour\n\
\n\
Benefits:\n\
\n\
    Employee discount\n\
    Paid time off\n\
\n\
Physical setting:\n\
\n\
    Casual dining restaurant\n\
\n\
Schedule:\n\
\n\
    8 hour shift\n\
    Day shift\n\
    Holidays\n\
    Monday to Friday\n\
    Night shift\n\
    Weekend availability\n\
\n\
Education:\n\
\n\
    High school or equivalent (Preferred)\n\
\n\
Experience:\n\
\n\
    Restaurant: 1 year (Required)";
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
