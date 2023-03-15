export type extr_def =
{
    Name: string,
    OperationQueues: op[][],
    Patterns: string[],
};

export type op_capture =
{
    PatternID: number,
    Offset: number,
};

export type op_pymodule =
{
    ScriptName: string,
};

export type op_data = op_pymodule | op_capture;


enum op_type
{
    pymodule = 0,
    capture,
};

export type op =
{
    Type: op_type,
    Data: op_data,
};

export type protex_api =
{
    GetScriptNames: () => any,
    WriteConfig: (ConfigStr: string) => any, WriteScript: (ScriptName: string, Src: string) => any,
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
