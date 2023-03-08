# Protex changelog

This project adheres to [semver](https://semver.org/)

## [0.5.0-alpha] - unreleased
### Added
- Visual scripting system

## [0.4.1-alpha] - 02-16-23
### Added
- Toolbar and actions changing what is displayed to the user ( example: target specific extractor
  to work on ).

## [0.4.0-alpha] - 02-14-23
### Added
- a Fox
- Extract/Tag conditions can now specify specific patterns.
- Script editing.
- Dedicated pattern editing area.

### Fixed
- Text tabs/new-lines are now properly displayed.
- Out of bounds index when using UNTIL OFFSET within a conditional statement.
- App writing artifacts to wrong dir.

### Removed
- Generate config button and text that would appear because configurations are now written by main
    thread instead of a web server.

### Changed
- Text scrollbars are now hidden
- Project name is now "protex"
- Extractor now allways resolves with a script.

### Added
- Pressing '~' during conditional statement editing now prompts an auto complete for the pattern
    to include within the statement.

## [0.3.1-alpha] - 02-08-23
### Removed
- Country/Language inputs within config, and refrences within extractor and packager.

### Changed
- Don't let index cache renderer.js

### Fixed
- User provided text is now properly rendering after clicking away.

## [0.3.0-alpha] - 02-06-23
### Changed
- Packager now returns an error on failed hs compilation rather than a crash.
- Web client is now a standalone electron application

### Removed
- Web server

## [0.2.0-alpha] - 01-29-23
### Added
- Basic tagging conditions
- Delete buttons for categories and extractors

## [0.1.1-alpha] - 01-23-23
### Added
- .gitignore
- Regex highlighting for selected patterns
- Server writes configurations built in the web interface to disk.
- Server can run packager and create artifacts from a web request.
- Server can call extractor from a web request.

### Changed
- Extractor's Zig Init API no longer requires null terminated artifact path.
- Packager exposes artifact creation functionality.
- Refactoring of python module selector population.
- When selecting text the pattern input which was last selected (if any) is filled with the user's
    text selection converted to a basic regex pattern.
- Set resuse address flag when initializing stream server.
- Refactor HTTP response creation.

### Removed
- Needless async functions

## [0.1.0-alpha] - 01-12-23
### Added
- Web client and server

### Fixed
- Throwing away scratch space refrence per database load.

## [0.0.5-alpha] - 01-06-23
### Added
- a README
- Full support for multiple extractor definitions.
- Json parsing on returned value from python callbacks.

### Changed
- Sempy run now writes to a utf8 encoded byte buffer rather than a wchar buffer.

### Fixed
- Extractor Unit test (again)
- sempy init/deinit crash

## [0.0.4-alpha] - 01-04-23
### Fixed
- Extractor Unit test
- Memory leaks caused by moving off of a backing buffer.

### Added
- Loading of arbitrary python modules
- CatBoxes...

### Changed
- Instances of Text paramaters are now marked as constant.
- Decoupled python modules from category definition blocks.
- Sempy now writes main module output to a buffer which is then exposed through extract api.

## [0.0.3-alpha] - 12-31-22
### Changed
- Artifact structure, the packager and deserializer now handle new artifact structure
- Improved error handling
- Simplified backing allocator logic
- Slab allocator now stores entire backing buffer slize instead of just it's ptr as an int

## [0.0.2-alpha] - 12-15-22
### Added
- VERY EARLY embeded python 11 support

## [0.0.1-alpha] - 11-25-22

### Added
- Slab alloactor
- Debug slab visualizer
- Init,Extract,Deinit
