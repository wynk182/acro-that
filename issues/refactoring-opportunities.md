# Refactoring Opportunities

This document identifies code duplication and unused methods that could be refactored to improve maintainability.

## 1. Duplicated Page-Finding Logic ✅ **COMPLETED**

### Status
**RESOLVED** - This refactoring has been completed:
- ✅ `DictScan.is_page?(body)` exists (line 320 in dict_scan.rb)
- ✅ `Document#find_all_pages` exists (line 693 in document.rb)
- ✅ `Document#find_page_by_number(page_num)` exists (line 725 in document.rb)
- ✅ `Base#find_page_by_number` delegates to Document
- ✅ `AddField#find_page_ref` now uses `find_page_by_number` (line 288)

### Original Issue
Multiple methods had similar logic for finding page objects in a PDF document.

### Resolution
All page-finding logic has been unified into `DictScan.is_page?` and `Document#find_all_pages` / `find_page_by_number`.

---

## 2. Duplicated Widget-Matching Logic

### Issue
Multiple methods have similar logic for finding widgets that belong to a field. Widgets can be matched by:
1. `/Parent` reference pointing to the field
2. `/T` (field name) matching the field name

### Locations
- `Document#list_fields` (lines 222-327) - Finds widgets and matches them to fields
- `Document#clear` (lines 472-495) - Finds widgets for removed fields
- `UpdateField#update_widget_annotations_for_field` (lines 220-247) - Finds widgets by /Parent
- `UpdateField#update_widget_names_for_field` (lines 249-280) - Finds widgets by /Parent and /T
- `RemoveField#remove_widget_annotations_from_pages` (lines 55-103) - Finds widgets by /Parent and /T
- `AddSignatureAppearance#find_widget_annotation` (lines 164-206) - Finds widgets by /Parent

### Pattern
The pattern of checking `/Parent` reference and matching by `/T` field name is repeated throughout.

### Suggested Refactor
Create utility methods in `Base` or a new `WidgetMatcher` module:
- `find_widgets_by_parent(field_ref)` - Find widgets with /Parent pointing to field_ref
- `find_widgets_by_name(field_name)` - Find widgets with /T matching field_name
- `find_widgets_for_field(field_ref, field_name)` - Find all widgets for a field (by parent or name)

### Benefits
- Centralized widget matching logic
- Consistent widget finding behavior
- Easier to extend matching criteria

---

## 3. Duplicated /Annots Array Manipulation

### Issue
Multiple methods handle adding or removing widget references from page `/Annots` arrays. The logic needs to handle:
1. Inline `/Annots` arrays: `/Annots [...]`
2. Indirect `/Annots` arrays: `/Annots X Y R` (reference to separate array object)

### Locations
- `AddField#add_widget_to_page` (lines 213-275) - Adds widget to /Annots
- `RemoveField#remove_widget_from_page_annots` (lines 125-155) - Removes widget from /Annots
- `Document#clear` (lines 555-633) - Removes widgets from /Annots during cleanup

### Pattern
All three methods have similar conditional logic:
```ruby
if page_body =~ %r{/Annots\s*\[(.*?)\]}m
  # Handle inline array
elsif page_body =~ %r{/Annots\s+(\d+)\s+(\d+)\s+R}
  # Handle indirect array
else
  # Create new /Annots array
end
```

### Suggested Refactor
Extend `DictScan` with methods:
- `DictScan.add_to_annots_array(page_body, widget_ref)` - Unified method to add widget to /Annots
- `DictScan.remove_from_annots_array(page_body, widget_ref)` - Unified method to remove widget from /Annots
- `DictScan.get_annots_array(page_body)` - Extract /Annots array (handles both inline and indirect)

### Benefits
- Single implementation of /Annots manipulation logic
- Consistent handling of edge cases
- Easier to test /Annots operations

---

## 4. Duplicated Box Parsing Logic ✅ **COMPLETED**

### Status
**RESOLVED** - This refactoring has been completed:
- ✅ `DictScan.parse_box(body, box_type)` exists (line 340 in dict_scan.rb)
- ✅ `Document#list_pages` now uses `parse_box` for all box types (lines 89-99 in document.rb)

### Original Issue
`Document#list_pages` had repeated code blocks for parsing different box types (MediaBox, CropBox, ArtBox, BleedBox, TrimBox).

### Resolution
Extracted the common box parsing logic into `DictScan.parse_box` helper method. All box type parsing in `Document#list_pages` now uses this shared method, reducing code duplication from ~45 lines to ~10 lines while maintaining existing functionality.

---

## 5. Duplicated next_fresh_object_number Implementation

### Issue
The `next_fresh_object_number` method is implemented identically in two places.

### Locations
- `Document#next_fresh_object_number` (lines 745-754)
- `Base#next_fresh_object_number` (lines 28-37)

### Pattern
Both methods have identical implementation. However, `Document` doesn't include `Base`, so both need to exist independently.

### Suggested Refactor
- Consider whether `Document` should use `Base`'s implementation via delegation
- Or: Keep both implementations if Document needs independent access

### Benefits
- Single implementation
- Consistent object numbering logic

### Note
This may be intentional since `Document` doesn't include `Base` - both classes need this functionality independently.

---

## 6. Unused Methods

### Issue
Some methods are defined but never called.

### Locations
- `AddSignatureAppearance#get_widget_rect_dimensions` (lines 218-223)
  - Defined but never used
  - `extract_rect` is used instead, which provides the same information

### Suggested Refactor
- Remove `get_widget_rect_dimensions` if it's truly unused
- Or: Verify if it was intended for future use and document it

### Benefits
- Cleaner codebase
- Less confusion about which method to use

---

## 7. Duplicated Base64 Decoding Logic

### Issue
`AddSignatureAppearance` has two similar methods for decoding base64 data.

### Locations
- `AddSignatureAppearance#decode_base64_data_uri` (lines 101-106)
- `AddSignatureAppearance#decode_base64_if_needed` (lines 108-119)

### Pattern
Both methods handle base64 decoding, with slightly different logic. Could potentially be unified.

### Suggested Refactor
- Consider merging into a single method that handles both cases
- Or: Document the distinction if both are needed

### Benefits
- Simpler API
- Less code duplication

---

## 8. Duplicated Regex Pattern for Object Reference

### Issue
The pattern for extracting object references `(\d+)\s+(\d+)\s+R` appears in many places.

### Locations
Throughout the codebase, used in:
- Extracting `/Parent` references
- Extracting `/P` (page) references  
- Extracting `/Pages` references
- Extracting `/Fields` array references
- And many more...

### Suggested Refactor
Create a utility method:
```ruby
def DictScan.extract_object_ref(str)
  # Extract object reference from string
  # Returns [obj_num, gen_num] or nil
end
```

### Benefits
- Consistent reference extraction
- Easier to update if PDF reference format changes
- More readable code

---

## Priority Recommendations

### High Priority
1. **Widget Matching Logic (#2)** - Most duplicated, used in many critical operations
2. **/Annots Array Manipulation (#3)** - Complex logic that's error-prone when duplicated


### Low Priority
6. **next_fresh_object_number (#5)** - Simple duplication (may be intentional)
7. **Object Reference Extraction (#8)** - Could improve consistency
8. **Unused Methods (#6)** - Cleanup task (`get_widget_rect_dimensions`)
9. **Base64 Decoding (#7)** - Minor duplication

### Completed ✅
- **Page-Finding Logic (#1)** - Successfully refactored into `DictScan.is_page?` and unified page-finding methods
- **Checkbox Appearance Creation (#9)** - Extracted common Form XObject building logic into `build_form_xobject` helper method
- **Box Parsing Logic (#4)** - Extracted common box parsing logic into `DictScan.parse_box` helper method
- **PDF Metadata Formatting (#10)** - Moved `format_pdf_key` and `format_pdf_value` to `DictScan` module as shared utilities

---

## 9. Duplicated Checkbox Appearance Creation Logic ✅ **COMPLETED**

### Status
**RESOLVED** - This refactoring has been completed:
- ✅ `AddField#build_form_xobject` exists (line 472 in add_field.rb)
- ✅ `AddField#create_checkbox_yes_appearance` now uses `build_form_xobject` (line 458)
- ✅ `AddField#create_checkbox_off_appearance` now uses `build_form_xobject` (line 469)

### Original Issue
The `create_checkbox_yes_appearance` and `create_checkbox_off_appearance` methods had duplicated Form XObject dictionary building logic.

### Resolution
Extracted the common Form XObject dictionary building logic into `build_form_xobject` helper method. Both checkbox appearance methods now use this shared method, reducing duplication while maintaining existing functionality.

---

## 10. PDF Metadata Formatting Methods Could Be Shared ✅ **COMPLETED**

### Status
**RESOLVED** - This refactoring has been completed:
- ✅ `DictScan.format_pdf_key(key)` exists (line 134 in dict_scan.rb)
- ✅ `DictScan.format_pdf_value(value)` exists (line 140 in dict_scan.rb)
- ✅ `AddField` now uses `DictScan.format_pdf_key` and `DictScan.format_pdf_value` (lines 145-146, 195-196)

### Original Issue
The `format_pdf_key` and `format_pdf_value` methods in `AddField` were useful utility functions that could be shared across the codebase.

### Resolution
Moved `format_pdf_key` and `format_pdf_value` from `AddField` to the `DictScan` module as module functions. This makes them reusable throughout the codebase and provides a single source of truth for PDF formatting rules. `AddField` now uses these shared utilities, maintaining existing functionality while improving code reusability.

---

## Notes
- All refactoring should be accompanied by tests to ensure behavior doesn't change
- Consider backward compatibility if any methods are moved between modules
- Some duplication may be intentional for performance reasons (avoid method call overhead) - evaluate before refactoring

