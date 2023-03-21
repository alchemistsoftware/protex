const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});
const std = @import("std");
const self = @This();

pub fn Init() !void {
    if (c.Py_IsInitialized() == 0) {
        // Initialize without registering signal handlers
        c.Py_InitializeEx(0);
        return;
    }
    return error.SempyUnknown;
}

pub fn Deinit() void {
    if (c.Py_FinalizeEx() != 0) {
        unreachable;
    }
    return;
}

fn PrintAndClearErr() void {
    c.PyErr_Print();
    c.PyErr_Clear();
}

pub const callback_fn = struct {
    FnPtr: *c.PyObject,
};

// TODO(cjb): return an optional callback for module's which don't have a main?
pub fn LoadModuleFromSource(NameZ: []const u8, SourceZ: []const u8) !self.callback_fn {
    // Check params are null terminated
    if ((NameZ[NameZ.len - 1] != 0) or
        (SourceZ[SourceZ.len - 1] != 0))
    {
        return error.SempyInvalid;
    }

    // Get dictonary of builtins from the current execution frame.
    const Builtins = c.PyEval_GetBuiltins();
    if (Builtins == null) {
        unreachable;
    }
    defer c.Py_DECREF(Builtins);

    // Lookup compile from builtins dictonary
    const Compile = c.PyDict_GetItemString(Builtins, "compile");
    if (Compile == null) {
        unreachable;
    }
    defer c.Py_DECREF(Compile);

    // Compiles source code into an AST object.
    const Code = c.PyObject_CallFunction(Compile, // function
        "sss", // arg format
        @ptrCast([*:0]const u8, SourceZ.ptr), // source code
        @ptrCast([*:0]const u8, NameZ.ptr), // filename
        "exec" // mode
    );
    if (Code == null) {
        self.PrintAndClearErr();
        return error.SempyInvalid; //SempyBadSource
    }
    defer c.Py_DECREF(Code);

    // Given a module name (possibly of the form package.module) and a code object read from
    // the built-in function compile(), load the module.
    const Module = c.PyImport_ExecCodeModule(@ptrCast([*:0]const u8, NameZ.ptr), Code);
    if (Module == null) {
        self.PrintAndClearErr();
        return error.SempyUnknown;
    }
    defer c.Py_DECREF(Module);

    // Get function ptr to module's main
    var MainFnPtr = c.PyObject_GetAttrString(Module, "protex_main");
    if (MainFnPtr == null) {
        self.PrintAndClearErr();
        return error.SempyInvalid; // Couldn't find module's main fn
    }

    c.Py_INCREF(MainFnPtr);
    return self.callback_fn{ .FnPtr = MainFnPtr };
}

pub fn UnloadCallbackFn(Callback: self.callback_fn) void {
    c.Py_DECREF(Callback.FnPtr);
}

pub fn Run(Callback: self.callback_fn, Text: []const u8, SO: c_ulonglong, EO: c_ulonglong, OutBuf: []u8) !usize {
    var nBytesCopied: isize = undefined;

    const Args = c.Py_BuildValue("(s#KK)", Text.ptr, @intCast(c.Py_ssize_t, Text.len), SO, EO);
    if (Args == null) {
        self.PrintAndClearErr();
        return error.SempyConvertArgs;
    }
    defer c.Py_DECREF(Args);

    var Result = c.PyObject_CallObject(Callback.FnPtr, Args);
    if (Result == null) {
        self.PrintAndClearErr();
        return error.SempyInvalid; // Bad return
    }
    defer c.Py_DECREF(Result);

    // Convert unicode into utf8 encoded string.
    var UTF8EncodedStr = c.PyUnicode_AsUTF8AndSize(Result, &nBytesCopied);
    if ((UTF8EncodedStr == null) or
        (nBytesCopied < 0))
    {
        self.PrintAndClearErr();
        return error.SempyUnknown; // Couldn't convert to utf8?
    }

    // Copy bytes into buf
    if (@intCast(usize, nBytesCopied) > OutBuf.len) {
        return error.SempyInvalid; // Out buf isn't big enough.
        // NOTE(cjb): could pass ally instead and return slice?
    }
    for (@ptrCast([*]const u8, UTF8EncodedStr)[0..@intCast(usize, nBytesCopied)], 0..) |B, I|
        OutBuf[I] = B;

    return @intCast(usize, nBytesCopied);
}
