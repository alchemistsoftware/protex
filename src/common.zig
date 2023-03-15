pub const op_pymodule = packed struct
{
    Index: usize,
};

pub const op_capture = packed struct
{
    PatternID: usize,
    Offset: usize,
};

pub const op_type = enum(usize)
{
    PyModule,
    Capture,
};

//
// Artifact header structs
//

pub const arti_op_q_header = packed struct
{
    nOps: usize,
};

/// Operation header

pub const arti_op_header = packed struct
{
    Type: op_type,
};

/// Extractor definition header

pub const arti_def_header = packed struct
{
    nExtractorNameBytes: usize,
    DatabaseSize: usize,
    nOperationQueues: usize,
    nPatterns: usize,
};

/// Python module header

pub const arti_py_module_header = packed struct
{
    nPyNameBytes: usize,
    nPySourceBytes: usize,
};

/// First item in a packager artifact

pub const arti_header = packed struct
{
    nExtractorDefs: usize,
    nPyModules: usize,
};

//
// Visual layout of an artifact
//

// *--------Artifact header---------*
// |Py module count (usize)         |
// |Extraction ctx count (usize)    |
// *--------------------------------*
//
//     *--------Py module header--------*
//     | N py name bytes (usize)        |
//     | N py source bytes (usize)      |
//     |--------------------------------|
//     | Py name (nBytes)               |
//     | Py source (nBytes)             |
//     *--------------------------------*
//
//     *--------Py module header--------*
//     |             ...                |
//     *--------------------------------*
//
//     *---Extraction context header----*
//     | N extractor name bytes (usize) |
//     | N database bytes (usize)       |
//     | N operation queues (usize)     |
//     | N patterns (usize)             |
//     |----Extraction context data-----|
//     | Extractor name (nBytes)        |
//     | HS database (nbytes)           |
//     *--------------------------------*
//
//         *------Operation Q header--------*
//         | N Operations (usize)           |
//         *--------------------------------*
//
//             *--------Operation header--------*
//             | Operation type (usize)         |
//             |---------Operation data---------|
//             | Operation data (arti_op)       |
//             *--------------------------------*
//
//             *--------Operation header--------*
//             |              ...               |
//             *--------------------------------*
//
//         *------Operation Q header--------*
//         |             ...                |
//         *--------------------------------*
//
//     *---Extraction context header----*
//     |             ...                |
//     *--------------------------------*
