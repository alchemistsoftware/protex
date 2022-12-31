const std = @import("std");
const self = @This();
const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

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
    if (c.Py_FinalizeEx() < 0)
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

    const Builtins = c.PyEval_GetBuiltins();
    const Compile = c.PyDict_GetItemString(Builtins, "compile");
    const Code = c.PyObject_CallFunction(Compile, "sss", @ptrCast([* :0]const u8, SourceZ.ptr),
        @ptrCast([* :0]const u8, NameZ.ptr), "exec");
    if (Code != null)
    {
        const Module = c.PyImport_ExecCodeModule(
            @ptrCast([* :0]const u8, NameZ.ptr), Code);
        defer c.Py_XDECREF(Module);
        if (Module == null)
        {
            return error.SempyUnknown;
        }
    }
    c.Py_XDECREF(Code);
    c.Py_DECREF(Compile);
    c.Py_DECREF(Builtins);
}

pub fn RunModule(Text: []const u8, NameZ: []const u8) !void
{
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

//            pValue = c.PyLong_FromUnsignedLong(@intCast(c_ulong, CategoryID));
//            if (pValue == null)
//            {
//                return error.SempyConvertArgs;
//            }

            pValue = c.PyObject_CallObject(pFunc, pArgs);
        }
    }
    if (c.PyErr_Occurred() != 0)
    {
        c.PyErr_Print(); // TODO(cjb): Don't print this here.
        return error.SempyUnknown;
    }
}
