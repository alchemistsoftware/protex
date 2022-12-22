#ifndef SEMPY_H
#include <stdlib.h>

const int SEMPY_SUCCESS = 0;        // Call was executed successfully
const int SEMPY_INVALID = -1;       // Bad paramater was passed or bad usage
const int SEMPY_UNKNOWN_ERROR = -2; // Unhandled internal error
const int SEMPY_NOMEM = -3;         // A memory allocation failed

int SempyInit();
int SempyDeinit();
int SempyLoadModuleFromSource(const char *Source, size_t Size);
int SempyRunModule(const char *Text, size_t Size, unsigned int CategoryID);

#define SEMPY_H
#endif
