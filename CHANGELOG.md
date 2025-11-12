# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.5] - 2025-11-12

### Changed
- Renamed gem from `acro_that` to `corp_pdf`
- Renamed module from `AcroThat` to `CorpPdf`
- Updated all internal references, documentation, and examples

## [1.0.4] - 2025-11-12

### Fixed
- Fixed `Encoding::CompatibilityError` when processing field values with special characters (e.g., "María", "José"). Special characters are now automatically transliterated to ASCII equivalents (e.g., "María" → "Maria") before encoding to PDF format, ensuring compatibility with PDF string encoding requirements.

### Added
- Added I18n gem as a runtime dependency for transliteration support
- Added `DictScan.transliterate_to_ascii` method to convert special characters to ASCII equivalents
- Automatic transliteration for text field values and radio button field export values

## [1.0.3] - 2025-11-07

### Fixed
- Fixed `/DA` (default appearance) metadata handling for text fields. When `/DA` is provided in metadata, it is now properly applied to both field dictionaries and widget annotations for text fields.

## [1.0.2] - 2025-11-06

### Fixed
- Fixed xref table generation to properly handle missing object numbers. The xref table now correctly marks missing objects as free entries, ensuring PDF compatibility with viewers that strictly validate xref tables.

### Changed
- Updated `.gitignore` to exclude image files (`.png`, `.jpg`) from version control

## [1.0.1] - 2025-11-05

### Fixed
- Fixed checkbox field appearance state handling
- Improved radio button field value handling and appearance updates
- Enhanced `update_field` to better handle checkbox and radio button state changes
- Fixed field type detection for button fields in `add_field`

### Changed
- Refactored checkbox and radio button field creation logic for better consistency

## [1.0.0] - 2025-11-05

### Added
- Added radio button field support with `group_id` option for creating mutually exclusive radio button groups
- Refactored field types into separate classes (`Text`, `Checkbox`, `Radio`, `Signature`) for better code organization and maintainability
- Added `Fields::Base` module with shared functionality for all field types
- Improved field creation and update logic with better separation of concerns

### Changed
- Major refactoring of field type handling - field types are now implemented as separate classes rather than inline conditionals
- Improved code organization and maintainability

## [0.1.8] - 2025-11-04

### Fixed
- Fixed PDF parsing error when PDFs are wrapped in multipart form data. PDFs uploaded via web forms (with boundary markers like `------WebKitFormBoundary...`) are now automatically extracted before processing, ensuring correct offset calculations for xref tables and streams.

## [0.1.7] - 2025-11-03

### Changed
- Memory optimization improvements for document processing and field operations

## [0.1.6] - 2025-11-01

### Added
- Added new utility methods to `DictScan` for improved PDF dictionary parsing and manipulation
- Enhanced `add_field` action with improved field creation logic
- Enhanced `update_field` action with better field value update handling

### Changed
- Major refactoring of `add_field` and `update_field` actions for improved code organization
- Refactored `Document` class to reduce code duplication
- Improved field handling and metadata processing

## [0.1.5] - 2025-11-01

### Fixed
- Fixed signature field image data parsing when adding signature fields. Image data (base64 or data URI) is now properly detected and parsed when creating signature fields, matching the behavior of `update_field`.
- Fixed multiline text field handling

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

## [0.1.3] - 2025-11-01

### Changed
- Version bump release

## [0.1.1] - 2025-10-31

### Added
- Initial release of CorpPdf
- Pure Ruby PDF AcroForm editing library
- Support for parsing, listing, adding, removing, and modifying form fields
- Signature field image appearance support (JPEG and PNG)
- PDF flattening functionality
- StringIO support for in-memory PDF processing

