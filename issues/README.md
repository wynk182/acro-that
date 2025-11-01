# Code Review Issues

This folder contains documentation of code cleanup and refactoring opportunities found in the codebase.

## Files

- **[refactoring-opportunities.md](./refactoring-opportunities.md)** - Detailed list of code duplication and refactoring opportunities

## Summary

### High Priority Issues
1. **Widget Matching Logic** - Duplicated across 6+ locations
2. **/Annots Array Manipulation** - Complex logic duplicated in 3 locations

### Medium Priority Issues
3. **Box Parsing Logic** - Repeated code blocks for 5 box types
4. **Checkbox Appearance Creation** - Significant duplication in new code
5. **PDF Metadata Formatting** - Could benefit from being shared utilities

### Low Priority Issues
6. Duplicated `next_fresh_object_number` implementation (may be intentional)
7. Object reference extraction pattern duplication
8. Unused method: `get_widget_rect_dimensions`
9. Base64 decoding logic duplication

### Completed ✅
- **Page-Finding Logic** - Successfully refactored into `DictScan.is_page?` and unified page-finding methods

## Quick Stats

- **10 refactoring opportunities** identified (1 completed, 9 remaining)
- **6+ locations** with widget matching duplication
- **3 locations** with /Annots array manipulation duplication
- **1 unused method** found
- **2 new issues** identified in recent code additions

## Next Steps

1. Review [refactoring-opportunities.md](./refactoring-opportunities.md) for detailed information
2. Prioritize refactoring based on maintenance needs
3. Create test coverage before refactoring
4. Refactor incrementally, starting with high-priority items

