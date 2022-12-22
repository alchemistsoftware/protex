#include "sempy.h"
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdbool.h>

// maintain module names's
// extractor_id, category_id, country, language ?

int
SempyInit()
{
    int Result = SEMPY_INVALID;
    if (!Py_IsInitialized())
    {
        Py_InitializeEx(0); // 0 - don't register signal handlers
        Result = SEMPY_SUCCESS;
    }
    return Result;
}

int
SempyDeinit()
{
    int Result = SEMPY_INVALID;
    if(Py_IsInitialized())
    {
        Result = SEMPY_SUCCESS;
        if (Py_FinalizeEx() < 0)
        {
            Result = SEMPY_UNKNOWN_ERROR;
        }
    }
    return Result;
}

int
SempyLoadModuleFromSource(const char *Source, size_t Size)
{
    int Result = SEMPY_UNKNOWN_ERROR;
    if (!Py_IsInitialized())
    {
        Result = SEMPY_INVALID;
        return Result;
    }

    PyObject *Builtins, *Compile;
    PyObject *Code, *Module;

    Builtins = PyEval_GetBuiltins();
    Compile = PyDict_GetItemString(Builtins, "compile");
    Code = PyObject_CallFunction(Compile, "sss", Source, "woot.py", "exec");
    if (Code != NULL)
    {
        Module = PyImport_ExecCodeModule("woot", Code);
        if (Module != NULL)
        {
            Result = SEMPY_SUCCESS;
        }
    }
    Py_DECREF(Compile);
    Py_DECREF(Builtins);
    Py_XDECREF(Code);
    Py_XDECREF(Module);

    return Result;
}

int SempyRunModule(const char *Text, size_t Size, unsigned int CategoryID)
{
    if (!Py_IsInitialized())
    {
        return 1;
    }

    PyObject *pModule, *pFunc;
    PyObject *pArgs, *pValue;

    PyObject *pName = PyUnicode_DecodeFSDefault("woot");
    pModule = PyImport_Import(pName);
    Py_DECREF(pName);
    if (pModule != NULL)
    {
        pFunc = PyObject_GetAttrString(pModule, "foo");
        /* pFunc is a new reference */

        if (pFunc) {
            pArgs = PyTuple_New(2);
            pValue = PyUnicode_FromStringAndSize(Text, Size);
            if (!pValue)
            {
                Py_DECREF(pArgs);
                Py_DECREF(pModule);
                fprintf(stderr, "Cannot convert argument\n");
                return 1;
            }
            PyTuple_SetItem(pArgs, 0, pValue);

            pValue = PyLong_FromUnsignedLong((unsigned long)CategoryID);
            if (!pValue)
            {
                Py_DECREF(pArgs);
                Py_DECREF(pModule);
                fprintf(stderr, "Cannot convert argument\n");
                return 1;
            }
            PyTuple_SetItem(pArgs, 1, pValue);

            pValue = PyObject_CallObject(pFunc, pArgs);
            Py_DECREF(pArgs);
            if (pValue != NULL) {
//                printf("Result of call: %ld\n", PyLong_AsLong(pValue));
                Py_DECREF(pValue);
            }
            else {
                Py_DECREF(pFunc);
                Py_DECREF(pModule);
                PyErr_Print();
                fprintf(stderr,"Call failed\n");
                return 1;
            }
        }
        else
        {
            if (PyErr_Occurred())
                PyErr_Print();
        }
        Py_XDECREF(pFunc);
        Py_XDECREF(pModule);
    }
    else {
        PyErr_Print();
        return 1;
    }
    return 0;
}
