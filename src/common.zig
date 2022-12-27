/// **********************************
///        -- Artifact shape --
/// **********************************
///
/// |--------Artifact header---------|
/// |Extraction ctx count (usize)    |
/// |--------------------------------|
///
///     |---Extraction context header----|
///     | N extractor name bytes (usize) |
///     | N database bytes (usize)       |
///     | N patterns (usize)             |
///     | N categories (usize)           |
///     |----Extraction context data-----|
///     | Country (2 bytes)              |
///     | Language (2 bytes)             |
///     | Extractor name (nBytes)        |
///     | HS database (nbytes)           |
///     |--------------------------------|
///
///         |--------Category header---------|
///         | N category name bytes (usize)  |
///         | N plugin source bytes (usize)  |
///         |---------Category data----------|
///         | Category name (nbytes)         |
///         | Plugin source (nBytes)         |
///         |--------------------------------|
///
///         |--------Category header---------|
///         |              ...               |
///         |--------------------------------|
///
///     |---Extraction context header----|
///     |             ...                |
///     |--------------------------------|
///


pub const gracie_extractor_category = struct
{
    nCategoryNameBytes: usize,
    nPyPluginSourceBytes: usize,
};

pub const  gracie_extraction_ctx = struct
{
    nExtractorNameBytes: usize,
    DatabaseSize: usize,
    nPatterns: usize,
    nCategories: usize,
};

pub const gracie_artifact_header = struct
{
    nExtractionCtxs: usize
};
