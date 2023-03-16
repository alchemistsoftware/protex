export type extr_def =
{
    Name: string,
    OperationQueues: op[][],
    Patterns: string[],

    // GUI specific data.

    OpBoxesSave: op_box_save[],
    SVGLinePosesSave: svg_line_pos_save[],
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

export type svg_line_pos_save =
{
    x1: number,
    y1: number,
    x2: number,
    y2: number,
};

export type op_box_save =
{
    OffsetLeft: number,
    OffsetTop: number,

    LeftNubLineIndices: number[],
    RightNubLineIndices: number[],
};

export type html_nub =
{
    LineIndices: number[],
} & HTMLElement;

export type html_op_box =
{
} & HTMLElement;
