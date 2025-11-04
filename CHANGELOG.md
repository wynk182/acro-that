# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.8] - 2025-11-04

### Fixed
- Fixed PDF parsing error when PDFs are wrapped in multipart form data. PDFs uploaded via web forms (with boundary markers like `------WebKitFormBoundary...`) are now automatically extracted before processing, ensuring correct offset calculations.
- Fixed xref stream parsing to properly validate objects are actually xref streams before attempting to parse them. Added fallback logic to find classic xref tables nearby when xref stream parsing fails.
- Fixed annotation removal to preserve non-widget annotations (such as highlighting, comments, etc.) when clearing fields. Only widget annotations associated with form fields are now removed.
- Improved PDF trailer Size calculation to handle object number gaps correctly.

## [0.1.5] - 2025-11-01

### Fixed
- Fixed signature field image data parsing when adding signature fields. Image data (base64 or data URI) is now properly detected and parsed when creating signature fields, matching the behavior of `update_field`.

### Added
- Added support for `metadata` option in `add_field` to pass PDF widget properties. This allows setting properties like field flags (`Ff`) for multiline text fields, alignment (`Q`), and other PDF widget options directly when creating fields.

## [0.1.4] - 2025-11-01

### Fixed
- Fixed bug where fields added to multi-page PDFs were all placed on the same page. Fields now correctly appear on their specified pages when using the `page` option in `add_field`.

### Changed
- Refactored page-finding logic to eliminate code duplication across `Document` and `AddField` classes
- Unified page discovery through `Document#find_all_pages` and `Document#find_page_by_number` methods
- Updated all page detection patterns to use centralized `DictScan.is_page?` utility method

### Added
- `DictScan.is_page?` utility method for consistent page object detection across the codebase
- `Document#find_all_pages` private method for unified page discovery in document order
- `Document#find_page_by_number` private method for finding pages by page number
- Exposed `find_page_by_number` through `Base` module for use in action classes

## [0.1.1] - 2025-10-31

### Added
- Initial release of AcroThat
- Pure Ruby PDF AcroForm editing library
- Support for parsing, listing, adding, removing, and modifying form fields
- Signature field image appearance support (JPEG and PNG)
- PDF flattening functionality
- StringIO support for in-memory PDF processing

