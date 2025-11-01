# Code Review Issues

This folder contains documentation of code cleanup and refactoring opportunities found in the codebase.

## Files

- **[refactoring-opportunities.md](./refactoring-opportunities.md)** - Detailed list of code duplication and refactoring opportunities

## Summary

### High Priority Issues
1. **Widget Matching Logic** - Duplicated across 6+ locations
2. **/Annots Array Manipulation** - Complex logic duplicated in 3 locations

### Medium Priority Issues
3. **Page-Finding Logic** - Similar logic in 4+ methods
4. **Box Parsing Logic** - Repeated code blocks for 5 box types

### Low Priority Issues
5. Duplicated `next_fresh_object_number` implementation
6. Object reference extraction pattern duplication
7. Unused method: `get_widget_rect_dimensions`
8. Base64 decoding logic duplication

## Quick Stats

- **8 refactoring opportunities** identified
- **6+ locations** with widget matching duplication
- **3 locations** with /Annots array manipulation duplication
- **1 unused method** found

## Next Steps

1. Review [refactoring-opportunities.md](./refactoring-opportunities.md) for detailed information
2. Prioritize refactoring based on maintenance needs
3. Create test coverage before refactoring
4. Refactor incrementally, starting with high-priority items

