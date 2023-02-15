//
// Artifact header structs
//

/// Artifact category header
pub const arti_cat_header = packed struct
{
    nCategoryNameBytes: usize,
    nCategoryConditionBytes: usize,
    MainPyModuleIndex: usize,
};

/// Artifact definition header
pub const arti_def_header = packed struct
{
    nExtractorNameBytes: usize,
    DatabaseSize: usize,
    nCategories: usize,
    nPatterns: usize,
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
//     | N patterns (usize)             |
//     |----Extraction context data-----|
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
//         *--------------------------------*
//
//         *--------Category header---------*
//         |              ...               |
//         *--------------------------------*
//
//     *---Extraction context header----*
//     |             ...                |
//     *--------------------------------*
