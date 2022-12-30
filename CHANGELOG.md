# Gracie changelog

This project adheres to [semver](https://semver.org/)

## [0.0.2-alpha] - 12-30-22
### Changed
- Artifact structure, the packager and deserializer now handle new artifact structure
- Improved error handling
- Simplified backing allocator logic
- Slab allocator now stores entire backing buffer slize instead of just it's ptr as an int

## [0.0.1-alpha] - 11-22-25

### Added
- Slab alloactor
- Debug slab visualizer
- Init,Extract,Deinit
