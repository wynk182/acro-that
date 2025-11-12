# PDF Object Streams Explained

## Overview

PDF Object Streams (also called "ObjStm") are a compression feature in PDFs that allows multiple PDF objects to be stored together in a single compressed stream. This reduces file size and improves performance. `CorpPdf` handles object streams transparently, so you don't need to worry about them when working with PDF objects—but understanding how they work helps explain how the library parses PDFs.

## What Are Object Streams?

Instead of storing objects individually in the PDF body:

```
5 0 obj
<< /Type /Annot /Subtype /Widget >>
endobj

6 0 obj
<< /Type /Annot /Subtype /Widget >>
endobj

7 0 obj
<< /Type /Annot /Subtype /Widget >>
endobj
```

Object streams allow multiple objects to be **packed together** in a single compressed stream:

```
10 0 obj
<< /Type /ObjStm /N 3 /First 20 >>
stream
[compressed header + object bodies]
endstream
endobj
```

Where:
- `/N 3` means there are 3 objects in this stream
- `/First 20` means the object data starts at byte offset 20 (the first 20 bytes are the header)
- The stream contains: header (object numbers + offsets) + object bodies

## Object Stream Structure

An object stream consists of two parts:

### 1. Header Section (First N bytes)

The header is a list of space-separated integers:
```
5 0 6 10 7 25
```

This means:
- Object 5 starts at offset 0 (relative to the start of object data)
- Object 6 starts at offset 10 (relative to the start of object data)
- Object 7 starts at offset 25 (relative to the start of object data)

Format: `obj_num offset obj_num offset ...` (pairs of object number and offset)

### 2. Object Data Section (Starting at /First)

The object data section contains the actual object bodies, concatenated together:
```
<< /Type /Annot /Subtype /Widget >><< /Type /Annot /Subtype /Widget >><< /Type /Annot /Subtype /Widget >>
```

The offsets in the header tell us where each object body starts within this data section.

### Complete Example

```
10 0 obj
<< /Type /ObjStm /N 3 /First 20 /Filter /FlateDecode >>
stream
[Compressed bytes containing:]
Header: "5 0 6 10 7 25 "
Data:   "<< /Type /Annot /Subtype /Widget >><< /Type /Annot /Subtype /Widget >><< /Type /Annot /Subtype /Widget >>"
endstream
endobj
```

After decompression:
- Bytes 0-19: Header (`"5 0 6 10 7 25 "`)
- Bytes 20+: Object data (`"<< /Type /Annot /Subtype /Widget >>..."`)
- Object 5 body: bytes 20-29 (offset 0 + 20 = 20, next object at offset 10)
- Object 6 body: bytes 30-59 (offset 10 + 20 = 30, next object at offset 25)
- Object 7 body: bytes 45+ (offset 25 + 20 = 45)

## How CorpPdf Parses Object Streams

### Step 1: Cross-Reference Table Parsing

When `ObjectResolver` parses the cross-reference table or xref stream, it identifies objects stored in object streams:

```ruby
# In parse_xref_stream_records
when 2 then @entries[ref] ||= Entry.new(type: :in_objstm, objstm_num: f1, objstm_index: f2)
```

Where:
- `f1` = object stream number (the container object)
- `f2` = index within the object stream (0 = first object, 1 = second object, etc.)

Example: If object 5 is at index 0 in object stream 10, then `Entry` stores:
- `type: :in_objstm`
- `objstm_num: 10` (the object stream container)
- `objstm_index: 0` (first object in the stream)

### Step 2: Lazy Loading

When you request an object body that's in an object stream, `ObjectResolver` calls `load_objstm`:

```ruby
def load_objstm(container_ref)
  return if @objstm_cache.key?(container_ref)  # Already cached
  
  # Get the object stream container's body
  body = object_body(container_ref)
  
  # Extract dictionary to get /N and /First
  dict_src = extract_dictionary(body)
  n = DictScan.value_token_after("/N", dict_src).to_i
  first = DictScan.value_token_after("/First", dict_src).to_i
  
  # Extract and decode stream data
  raw = decode_stream_data(dict_src, extract_stream_body(body))
  
  # Parse the object stream
  parsed = CorpPdf::ObjStm.parse(raw, n: n, first: first)
  
  # Cache the result
  @objstm_cache[container_ref] = parsed
end
```

### Step 3: Stream Decoding

The `decode_stream_data` method handles:
1. **Extracting stream body**: Removes `stream` and `endstream` keywords
2. **Decompression**: If `/Filter /FlateDecode` is present, decompress using zlib
3. **PNG Predictor**: If `/Predictor` is present (10-15), apply PNG predictor decoding

Example:
```ruby
def decode_stream_data(dict_src, stream_chunk)
  # Extract body between stream...endstream
  body = extract_stream_body(stream_chunk)
  
  # Decompress if FlateDecode
  data = if dict_src =~ %r{/Filter\s*/FlateDecode}
           Zlib::Inflate.inflate(body)
         else
           body
         end
  
  # Apply PNG predictor if present
  if dict_src =~ %r{/Predictor\s+(\d+)}
    # Decode PNG predictor (Sub, Up, Average, Paeth)
    data = apply_png_predictor(data, columns)
  end
  
  data
end
```

### Step 4: Object Stream Parsing (`ObjStm.parse`)

The `ObjStm.parse` method is the heart of object stream parsing:

```ruby
def self.parse(bytes, n:, first:)
  # Extract header (first N bytes)
  head = bytes[0...first]
  
  # Parse space-separated integers: obj_num offset obj_num offset ...
  entries = head.strip.split(/\s+/).map!(&:to_i)
  
  # Extract each object body
  refs = []
  n.times do |i|
    obj = entries[2 * i]        # Object number
    off = entries[(2 * i) + 1]  # Offset in data section
    
    # Calculate next offset (or end of data)
    next_off = i + 1 < n ? entries[(2 * (i + 1)) + 1] : (bytes.bytesize - first)
    
    # Extract object body: start at (first + off), length is (next_off - off)
    body = bytes[first + off, next_off - off]
    
    refs << { ref: [obj, 0], body: body }
  end
  
  refs
end
```

**Step-by-step example:**

Given:
- `bytes` = decompressed stream data
- `n = 3` (3 objects)
- `first = 20` (data starts at byte 20)
- Header: `"5 0 6 10 7 25 "` (12 bytes, padded to 20)

Processing:
1. Extract header: `bytes[0...20]` → `"5 0 6 10 7 25 "`
2. Parse entries: `[5, 0, 6, 10, 7, 25]`
3. For `i=0` (first object):
   - `obj = entries[0]` = 5
   - `off = entries[1]` = 0
   - `next_off = entries[3]` = 10 (offset of next object)
   - `body = bytes[20 + 0, 10 - 0]` = bytes[20...30]
4. For `i=1` (second object):
   - `obj = entries[2]` = 6
   - `off = entries[3]` = 10
   - `next_off = entries[5]` = 25
   - `body = bytes[20 + 10, 25 - 10]` = bytes[30...45]
5. For `i=2` (third object):
   - `obj = entries[4]` = 7
   - `off = entries[5]` = 25
   - `next_off = bytes.bytesize - first` (end of data)
   - `body = bytes[20 + 25, ...]` = bytes[45...end]

Result:
```ruby
[
  { ref: [5, 0], body: "<< /Type /Annot /Subtype /Widget >>" },
  { ref: [6, 0], body: "<< /Type /Annot /Subtype /Widget >>" },
  { ref: [7, 0], body: "<< /Type /Annot /Subtype /Widget >>" }
]
```

### Step 5: Object Retrieval

When `object_body(ref)` is called for an object in an object stream:

```ruby
def object_body(ref)
  case (e = @entries[ref])&.type
  when :in_file
    # Regular object: extract from file
    extract_from_file(e.offset)
  when :in_objstm
    # Object stream: load stream (if not cached), then get object by index
    load_objstm([e.objstm_num, 0])
    @objstm_cache[[e.objstm_num, 0]][e.objstm_index][:body]
  end
end
```

The index (`objstm_index`) tells us which object in the parsed array to return.

## Why Object Streams Matter

### Benefits

1. **File Size**: Compressing multiple objects together is more efficient than compressing each individually
2. **Performance**: Fewer objects to parse when opening the PDF
3. **Common in Modern PDFs**: Most PDFs created by modern tools use object streams

### Transparency in CorpPdf

`CorpPdf` handles object streams automatically:
- You don't need to know if an object is in a stream or not
- `object_body(ref)` returns the object body the same way regardless
- Object streams are cached after first load (no repeated parsing)
- The same `DictScan` methods work on extracted object bodies

## Cross-Reference Streams vs Object Streams

**Important distinction:**

1. **XRef Streams** (`/Type /XRef`): Used to find where objects are located in the PDF
   - Contains byte offsets or references to object streams
   - Replaces classic xref tables

2. **Object Streams** (`/Type /ObjStm`): Used to store actual object bodies
   - Contains compressed object dictionaries
   - Referenced by xref streams or classic xref tables

Both use the same stream format (compressed, potentially with PNG predictor), but serve different purposes.

## PNG Predictor

PNG Predictor is a compression technique that predicts values based on previous values to improve compression. `CorpPdf` supports all 5 PNG predictor types:

1. **Type 0 (None)**: No prediction
2. **Type 1 (Sub)**: Predict from left
3. **Type 2 (Up)**: Predict from above
4. **Type 3 (Average)**: Predict from average of left and above
5. **Type 4 (Paeth)**: Predict using Paeth algorithm

The `apply_png_predictor` method decodes predictor-encoded data row by row, using the `/Columns` parameter to determine row width.

## Summary

Object streams allow PDFs to store multiple objects in compressed streams. `CorpPdf` handles them by:

1. **Identifying** objects in streams via xref parsing
2. **Lazy loading** stream containers when needed
3. **Decoding** compressed stream data (zlib + PNG predictor)
4. **Parsing** the header to extract object offsets
5. **Extracting** individual object bodies by offset
6. **Caching** parsed streams for performance

The parsing itself is straightforward:
- Header is space-separated integers (object numbers and offsets)
- Object data follows the header
- Extract each object body using its offset

Just like `DictScan`, object stream parsing is **text traversal**—once the stream is decompressed, it's just parsing space-separated numbers and extracting substrings by offset.

