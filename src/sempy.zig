const self = @This();
const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

pub const module_ctx = struct
{
    Source: [*:0]const u8,
    Name: [*:0]const u8,
};

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

pub fn LoadModuleFromSource(SM: *module_ctx) !void
{
    //  Is uninitialized?
    if (c.Py_IsInitialized() == 0)
    {
        return error.SempyInvalid;
    }

    const Builtins = c.PyEval_GetBuiltins();
    const Compile = c.PyDict_GetItemString(Builtins, "compile");
    const Code = c.PyObject_CallFunction(Compile, "sss", SM.Source, "", "exec");
    if (Code != null)
    {
        const Module = c.PyImport_ExecCodeModule(SM.Name, Code);
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

pub fn RunModule(Text: []u8, CategoryID: c_uint) !void
{
    _ = CategoryID;
    if (c.Py_IsInitialized() == 0)
    {
        return error.SempyInvalid;
    }

    const pName = c.PyUnicode_DecodeFSDefault("hourly"); //TODO(cjb): Get module name somehow
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
//            if (c.PyTuple_SetItem(pArgs, 1, pValue) == -1)
//            {
//                unreachable;
//            }

            pValue = c.PyObject_CallObject(pFunc, pArgs);
//            if (pValue != NULL) {
//                printf("Result of call: %ld\n", PyLong_AsLong(pValue));
//                Py_DECREF(pValue);
//            }
        }
        else //TODO(cjb): how should this be captured??? -- error str?
        {
            if (c.PyErr_Occurred() != 0)
            {
                c.PyErr_Print();
                return error.SempyUnknown;
            }
        }
    }
    else //DITTO
    {
        c.PyErr_Print();
        return error.SempyUnknown;
    }
}
