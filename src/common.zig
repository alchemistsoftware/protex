//
// Artifact header structs
//

/// Artifact category header
pub const gracie_extractor_cat_header = packed struct
{
    nCategoryNameBytes: usize,
    nPyPluginSourceBytes: usize,
};

/// Artifact definition header
pub const gracie_extractor_def_header = packed struct
{
    nExtractorNameBytes: usize,
    DatabaseSize: usize,
    nPatterns: usize,
    nCategories: usize,
};

/// Artifact header
pub const gracie_arti_header = packed struct
{
    nExtractorDefs: usize
};
