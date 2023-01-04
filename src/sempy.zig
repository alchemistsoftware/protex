const std = @import("std");
const self = @This();
const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

// BUG(cjb): Calling Init, Deinit than Init after loading & running a module results in a double free
// from within the cpython api. Hopefully I'm doing something painfully wrong somewhere...
// SEE: https://docs.python.org/3/c-api/intro.html#debugging-builds

pub fn Init() !void
{
    if (c.Py_IsInitialized() == 0)
    {
        // Initialize without registering signal handlers
        c.Py_InitializeEx(0);
        return;
    }
    return error.SempyUnknown;
}

pub fn Deinit() !void
{
    _ = c.PyGC_Collect();
    if (c.Py_FinalizeEx() != 0)
    {
        return error.SempyUnknown;
    }
    return;
}

pub fn LoadModuleFromSource(NameZ: []const u8, SourceZ: []const u8) !void
{
    //  Is uninitialized?
    if (c.Py_IsInitialized() == 0)
    {
        return error.SempyUnknown;
    }

    // Check params are null terminated
    if ((NameZ[NameZ.len - 1] != 0) or
        (SourceZ[SourceZ.len - 1] != 0))
    {
        return error.SempyInvalid;
    }

    // Get dictonary of builtins from the current execution frame.
    const Builtins = c.PyEval_GetBuiltins();
    if (Builtins == null)
    {
        unreachable;
    }
    defer c.Py_DECREF(Builtins);

    // Lookup compile from builtins dictonary
    const Compile = c.PyDict_GetItemString(Builtins, "compile");
    if (Compile == null)
    {
        unreachable;
    }
    defer c.Py_DECREF(Compile);

    // Compiles source code into an AST object.
    const Code = c.PyObject_CallFunction(Compile, // function
        "sss",                                    // arg format
        @ptrCast([* :0]const u8, SourceZ.ptr),    // source code
        @ptrCast([* :0]const u8, NameZ.ptr),      // filename
        "exec"                                    // mode
    );
    if (c.PyErr_Occurred() != null)
    {
        c.PyErr_Print();
        return error.SempyInvalid; //SempyBadSource
    }
    defer c.Py_DECREF(Code);

    // Given a module name (possibly of the form package.module) and a code object read from
    // the built-in function compile(), load the module.
    const Module = c.PyImport_ExecCodeModule(@ptrCast([* :0]const u8, NameZ.ptr), Code);
    defer c.Py_XDECREF(Module);
    if (c.PyErr_Occurred() != null)
    {
        c.PyErr_Print();
        return error.SempyInvalid; //SempyBadSource
    }
}

pub fn RunModule(Text: []const u8, NameZ: []const u8, OutBuf: []u32) !usize
{
    var Result: isize = 0;

    if (c.Py_IsInitialized() == 0)
    {
        return error.SempyUnknown;
    }

    const pName = c.PyUnicode_DecodeFSDefault(@ptrCast([* :0]const u8, NameZ.ptr));
    defer c.Py_XDECREF(pName);

    const pModule = c.PyImport_Import(pName);
    defer c.Py_XDECREF(pModule);
    if (pModule != null)
    {
        const pFunc = c.PyObject_GetAttrString(pModule, "main");
        defer c.Py_DECREF(pFunc);
        if (pFunc != null)
        {
            const pArgs = c.PyTuple_New(1);
            defer c.Py_DECREF(pArgs);

            var pValue = c.PyUnicode_FromStringAndSize(Text.ptr, @intCast(isize, Text.len));
            defer c.Py_XDECREF(pValue);
            if (pValue == null)
            {
                return error.SempyConvertArgsSempyMain;
            }
            if (c.PyTuple_SetItem(pArgs, 0, pValue) == -1)
            {
                unreachable;
            }

            // Call module's main
            var pUni = c.PyObject_CallObject(pFunc, pArgs);
            defer c.Py_DECREF(pUni);

            // Copy unicode object's bytes into OutBuf
            Result = c.PyUnicode_AsWideChar(pUni, @ptrCast(?[*]c_int, OutBuf.ptr),
                @intCast(isize, OutBuf.len));
            if (Result == -1)
            {
                unreachable;
            }
        }
    }
    if (c.PyErr_Occurred() != 0)
    {
        c.PyErr_Print();
        return error.SempyUnknown;
    }

    return @intCast(usize, Result);
}
