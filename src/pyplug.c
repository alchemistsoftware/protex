#define PY_SSIZE_T_CLEAN
#include <Python.h>

int
PyPlugRun(const char *Text, size_t Size)
{
    PyObject *pModule, *pFunc;
    PyObject *pArgs, *pValue;

    Py_Initialize();

    // fake module
    char *source = "def foo(Text: str) -> None:\n\tprint(Text + ' asdf')";
    char *filename = "woot.py";

    // perform module load
    PyObject *builtins = PyEval_GetBuiltins();
    PyObject *compile = PyDict_GetItemString(builtins, "compile");
    PyObject *code = PyObject_CallFunction(compile, "sss", source, filename, "exec");
    pModule = PyImport_ExecCodeModule("woot", code);
    Py_DECREF(code);
    Py_DECREF(compile);
    Py_DECREF(builtins);

    if (pModule != NULL)
    {
        pFunc = PyObject_GetAttrString(pModule, "foo");
        /* pFunc is a new reference */

        if (pFunc) {
            pArgs = PyTuple_New(1);
            pValue = PyUnicode_FromStringAndSize(Text, Size);
            if (!pValue)
            {
                Py_DECREF(pArgs);
                Py_DECREF(pModule);
                fprintf(stderr, "Cannot convert argument\n");
                return 1;
            }
            PyTuple_SetItem(pArgs, 0, pValue);
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
        else {
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
    if (Py_FinalizeEx() < 0) {
        return 120;
    }
    return 0;
}
