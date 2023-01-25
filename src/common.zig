//
// Artifact header structs
//

pub const arti_cat_on_match = enum(c_int)
{
    Script,
    Conditional
};

/// Artifact category header
pub const arti_cat_header = packed struct
{
    nCategoryNameBytes: usize,
    nCategoryConditionBytes: usize,
};

/// Artifact definition header
pub const arti_def_header = packed struct
{
    nExtractorNameBytes: usize,
    DatabaseSize: usize,
    nCategories: usize,
};

/// Artifact python module header
pub const arti_py_module_header = packed struct
{
    nPyNameBytes: usize,
    nPySourceBytes: usize,
};

/// First header in a packager artifact
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
//     | N categories (usize)           |
//     |----Extraction context data-----|
//     | Country (2 bytes)              |
//     | Language (2 bytes)             |
//     | Extractor name (nBytes)        |
//     | HS database (nbytes)           |
//     *--------------------------------*
//
//         *--------Category header---------*
//         | N category name bytes (usize)  |
//         | N condition bytes (usize)      |
//         |---------Category data----------|
//         | Category name (nbytes)         |
//         | Conditions (nbytes)            |
//         | N patterns (usize)             |
//         | Main py module index (isize)   |
//         | OnMatch type (c_int)           |
//         *--------------------------------*
//
//         *--------Category header---------*
//         |              ...               |
//         *--------------------------------*
//
//     *---Extraction context header----*
//     |             ...                |
//     *--------------------------------*
