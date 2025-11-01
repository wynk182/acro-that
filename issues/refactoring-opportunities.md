# Refactoring Opportunities

This document identifies code duplication and unused methods that could be refactored to improve maintainability.

## 1. Duplicated Page-Finding Logic

### Issue
Multiple methods have similar logic for finding page objects in a PDF document.

### Locations
- `Document#list_pages` (lines 75-104)
- `Document#collect_pages_from_tree` (lines 691-712)
- `Document#find_page_number_for_ref` (lines 714-728)
- `AddField#find_page_ref` (lines 155-211)

### Pattern
The pattern `body.include?("/Type /Page") || body =~ %r{/Type\s*/Page(?!s)\b}` appears in multiple places with slight variations.

### Suggested Refactor
Create a shared module or utility methods in `DictScan`:
- `DictScan.is_page?(body)` - Check if a body represents a page object
- `Document#find_all_pages` - Unified method to find all page objects
- `Document#find_page_by_number(page_num)` - Find a specific page by number

### Benefits
- Single source of truth for page detection logic
- Easier to maintain and update page-finding behavior
- Consistent page ordering across methods

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

## 4. Duplicated Box Parsing Logic

### Issue
`Document#list_pages` has repeated code blocks for parsing different box types (MediaBox, CropBox, ArtBox, BleedBox, TrimBox).

### Locations
- `Document#list_pages` (lines 120-165)

### Pattern
Each box type uses identical logic:
```ruby
if body =~ %r{/MediaBox\s*\[(.*?)\]}
  box_values = ::Regexp.last_match(1).scan(/[-+]?\d*\.?\d+/).map(&:to_f)
  if box_values.length == 4
    llx, lly, urx, ury = box_values
    media_box = { llx: llx, lly: lly, urx: urx, ury: ury }
  end
end
```

### Suggested Refactor
Create a helper method:
```ruby
def parse_box(body, box_type)
  pattern = %r{/#{box_type}\s*\[(.*?)\]}
  return nil unless body =~ pattern
  
  box_values = ::Regexp.last_match(1).scan(/[-+]?\d*\.?\d+/).map(&:to_f)
  return nil unless box_values.length == 4
  
  llx, lly, urx, ury = box_values
  { llx: llx, lly: lly, urx: urx, ury: ury }
end
```

### Benefits
- Reduces code duplication from ~45 lines to ~10 lines per box type
- Easier to add new box types
- Consistent parsing logic

---

## 5. Duplicated next_fresh_object_number Implementation

### Issue
The `next_fresh_object_number` method is implemented identically in two places.

### Locations
- `Document#next_fresh_object_number` (lines 730-739)
- `Base#next_fresh_object_number` (lines 28-37)

### Pattern
Both methods have identical implementation:
```ruby
def next_fresh_object_number
  max_obj_num = 0
  resolver.each_object do |ref, _|
    max_obj_num = [max_obj_num, ref[0]].max
  end
  patches.each do |p|
    max_obj_num = [max_obj_num, p[:ref][0]].max
  end
  max_obj_num + 1
end
```

### Suggested Refactor
- Remove `Document#next_fresh_object_number` - it's only called within `Document` but could use `Base`'s implementation
- Or: Document already has access to resolver and patches, so remove duplication by making Document use Base's method

### Benefits
- Single implementation
- Consistent object numbering logic

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

### Medium Priority
3. **Page-Finding Logic (#1)** - Used in multiple places, but less frequently
4. **Box Parsing Logic (#4)** - Simple duplication, easy to refactor

### Low Priority
5. **next_fresh_object_number (#5)** - Simple duplication
6. **Object Reference Extraction (#8)** - Could improve consistency
7. **Unused Methods (#6)** - Cleanup task
8. **Base64 Decoding (#7)** - Minor duplication

---

## Notes
- All refactoring should be accompanied by tests to ensure behavior doesn't change
- Consider backward compatibility if any methods are moved between modules
- Some duplication may be intentional for performance reasons (avoid method call overhead) - evaluate before refactoring

