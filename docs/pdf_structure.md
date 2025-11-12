# PDF File Structure

## Overview

PDF (Portable Document Format) files have a reputation for being complex binary formats, but at their core, they are **text-based files with a structured syntax**. Understanding this fundamental fact is key to understanding how PDF works.

While PDFs can contain binary data (like compressed streams, images, and fonts), the **structure** of a PDF—its objects, dictionaries, arrays, and references—is defined using plain text syntax.

## PDF File Anatomy

A PDF file consists of several main parts:

1. **Header**: `%PDF-1.4` (or similar version)
2. **Body**: A collection of PDF objects (the actual content)
3. **Cross-Reference Table (xref)**: Points to byte offsets of objects
4. **Trailer**: Contains the root object reference and metadata
5. **EOF Marker**: `%%EOF`

### PDF Objects

The body contains PDF objects. Each object has:
- An object number and generation number (e.g., `5 0 obj`)
- Content (dictionary, array, stream, etc.)
- An `endobj` marker

Example:
```
5 0 obj
<< /Type /Page /Parent 3 0 R /MediaBox [0 0 612 792] >>
endobj
```

## PDF Dictionaries

**PDF dictionaries are the heart of PDF structure.** They're defined using angle brackets:

```
<< /Key1 value1 /Key2 value2 /Key3 value3 >>
```

Think of them like JSON objects or Ruby hashes, but with PDF-specific syntax:
- Keys are PDF names (always start with `/`)
- Values can be: strings, numbers, booleans, arrays, dictionaries, or object references
- Whitespace is generally ignored (but required between tokens)

### Dictionary Examples

**Simple dictionary:**
```
<< /Type /Page /Width 612 /Height 792 >>
```

**Nested dictionary:**
```
<< 
  /Type /Annot
  /Subtype /Widget
  /Rect [100 500 200 520]
  /AP <<
    /N <<
      /Yes 10 0 R
      /Off 11 0 R
    >>
  >>
>>
```

**Dictionary with array:**
```
<< /Kids [5 0 R 6 0 R 7 0 R] >>
```

**Dictionary with string values:**
```
<< /Title (My Document) /Author (John Doe) >>
```

The parentheses `()` denote literal strings in PDF syntax. Hex strings use angle brackets: `<>`.

## PDF Text-Based Syntax

Despite being "binary" files, PDFs use text-based syntax for their structure. This means:

1. **Dictionaries are text**: `<< ... >>` are just character sequences
2. **Arrays are text**: `[ ... ]` are just character sequences  
3. **References are text**: `5 0 R` means "object 5, generation 0"
4. **Strings can be text or hex**: `(Hello)` or `<48656C6C6F>`

### Why This Matters

Because PDF dictionaries are just text with delimiters (`<<`, `>>`), we can parse them using **simple text traversal algorithms**—no complex parser generator, no AST construction, just:

1. Find opening `<<`
2. Track nesting depth by counting `<<` and `>>`
3. When depth reaches zero, we've found a complete dictionary
4. Repeat

## PDF Object References

PDFs use references to link objects together:
```
5 0 R
```

This means:
- Object number: `5`
- Generation number: `0` (usually 0 for non-incremental PDFs)
- `R` means "reference"

When you see `/Parent 5 0 R`, it means the `Parent` key references object 5.

## PDF Arrays

Arrays are space-separated lists in square brackets:
```
[0 0 612 792]
```

Can contain any PDF value type:
```
[5 0 R 6 0 R]
[/Yes /Off]
[(Hello) (World)]
```

## PDF Strings

PDF strings come in two flavors:

### Literal Strings (parentheses)
```
(Hello World)
(Line 1\nLine 2)
```

Can contain escape sequences: `\n`, `\r`, `\t`, `\\(`, `\\)`, octal `\123`.

### Hex Strings (angle brackets)
```
<48656C6C6F>
<FEFF00480065006C006C006F>
```

The hex string `<FEFF...>` with BOM indicates UTF-16BE encoding.

## PDF Names

PDF names start with `/`:
```
/Type
/Subtype
/Widget
```

Names can contain most characters except special delimiters.

## Stream Objects

Some PDF objects contain **streams** (binary or text data):
```
10 0 obj
<< /Length 100 /Filter /FlateDecode >>
stream
[compressed binary data here]
endstream
endobj
```

For parsing structure (dictionaries), we typically strip or ignore stream bodies because they can contain arbitrary binary data that would confuse text-based parsing.

## Why CorpPdf Works

`CorpPdf` works because **PDF dictionaries are just text patterns**. Despite looking complicated, the algorithms are straightforward:

### Finding Dictionaries

The `each_dictionary` method:
1. Searches for `<<` (start of dictionary)
2. Tracks nesting depth: `<<` increments, `>>` decrements
3. When depth returns to 0, we've found a complete dictionary
4. Yield it and continue searching

This is **pure text traversal**—no PDF-specific knowledge beyond "dictionaries use `<<` and `>>`".

### Extracting Values

The `value_token_after` method:
1. Finds a key (like `/V`)
2. Skips whitespace
3. Based on the next character, extracts the value:
   - `(` → Extract literal string (handle escaping)
   - `<` → Extract hex string or dictionary
   - `[` → Extract array (match brackets)
   - `/` → Extract name
   - Otherwise → Extract atom (number, reference, etc.)

Again, this is just **text pattern matching** with some bracket/depth tracking.

### Why It Seems Complicated

The complexity comes from:
1. **Handling edge cases**: Escaped characters, nested structures, various value types
2. **Preserving exact formatting**: When replacing values, we must maintain valid PDF syntax
3. **Encoding/decoding**: PDF strings have special encoding rules (UTF-16BE BOM, escapes)
4. **Safety checks**: Verifying dictionaries are still valid after modification

But the **core concept** is simple: PDF dictionaries are text, so we can parse them with text traversal.

## Example: Walking Through a PDF Dictionary

Given this PDF dictionary text:
```
<< /Type /Annot /Subtype /Widget /V (Hello World) /Rect [100 500 200 520] >>
```

How `CorpPdf` would parse it:

1. **`each_dictionary` finds it:**
   - Finds `<<` at position 0
   - Depth: 0 → 1 (after `<<`)
   - Scans forward...
   - Finds `>>` at position 64
   - Depth: 1 → 0
   - Yields: `"<< /Type /Annot /Subtype /Widget /V (Hello World) /Rect [100 500 200 520] >>"`

2. **`value_token_after("/V", dict)` extracts value:**
   - Finds `/V` (followed by space)
   - Skips whitespace
   - Next char is `(`, so extract literal string
   - Scan forward, handle escaping, match closing `)`
   - Returns: `"(Hello World)"`

3. **`decode_pdf_string("(Hello World)")` decodes:**
   - Starts with `(`, ends with `)`
   - Extract inner: `"Hello World"`
   - Unescape (no escapes here)
   - Check for UTF-16BE BOM (none)
   - Return: `"Hello World"`

## Conclusion

PDF files are **structured text files** with binary data embedded in streams. The structure itself—dictionaries, arrays, strings, references—is all text-based syntax. This is why `CorpPdf` can use simple text traversal to parse and modify PDF dictionaries without needing a full PDF parser.

The apparent complexity in `CorpPdf` comes from:
- Handling PDF's various value types
- Proper encoding/decoding of strings
- Careful preservation of structure during edits
- Edge case handling (escaping, nesting, etc.)

But the **fundamental approach** is elegantly simple: treat PDF dictionaries as text patterns and parse them with character-by-character traversal.

