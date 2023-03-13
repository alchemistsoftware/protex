
export type cat_def =
{
    Name: string,
    Conditions: string,
};

export type extr_def =
{
    Name: string,
    Categories: cat_def[],
    Patterns: string[],
};

export type op_capture =
{
    Pattern: string,
};

export type op_pymodule =
{
    PyModule: string,
};

export type op = op_pymodule | op_capture;

//export type op =
//{
//    Data: op_data,
//};

export type protex_api =
{
    GetScriptNames: () => any,
    WriteConfig: (ConfigStr: string) => any,
    WriteScript: (ScriptName: string, Src: string) => any,
    ReadScript: (ScriptName: string) => any,
    RunExtractor: (ConfigName: string, Text: string) => any,
};

export type protex_window =
{
    ProtexAPI: protex_api,
} & Window;

export type protex_state =
{
    ScriptNames: string[],
    Extractors: extr_def[],
};

export type html_nub =
{
    LineIndices: number[],
} & HTMLElement;

export type html_op_box = //TODO(cjb): Impl me!
{
    LeftNub: html_nub,
    RightNub: html_nub,
} & HTMLElement;
