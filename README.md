# AcroThat

A minimal pure Ruby library for parsing and editing PDF AcroForm fields using only Ruby stdlib.

## Features

- ✅ **Pure Ruby** - No external dependencies beyond stdlib
- ✅ **StringIO Only** - Works entirely in memory, no temp files
- ✅ **PDF AcroForm Support** - Parse, list, add, remove, and modify form fields
- ✅ **Minimal PDF Engine** - Basic PDF parser/writer for AcroForm manipulation
- ✅ **Ruby 3.1+** - Modern Ruby support

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'acro_that'
```

And then execute:

```bash
bundle install
```

Or install it directly:

```bash
gem install acro_that
```

## Usage

### Basic Usage

```ruby
require 'acro_that'
require 'stringio'

# Open a PDF from StringIO
pdf_data = File.binread("form.pdf")
io = StringIO.new(pdf_data)
doc = AcroThat::Document.open(io)

# List all form fields
fields = doc.list_fields
fields.each do |field|
  puts "#{field.fqn} (#{field.type})"
end

# Add a new field
doc.replace_field("NameField", rect: [100, 500, 200, 520], value: "John Doe")

# Remove a field
doc.remove_field("OldField")

# Write the modified PDF
output = doc.write_to_string_io
File.binwrite("output.pdf", output.string)
```

### API Reference

#### `AcroThat::Document.open(io)`
Opens a PDF document from a StringIO object.

#### `#list_fields`
Returns an array of `Field` objects representing all form fields in the document.

#### `#remove_field(name)`
Removes a form field by its name (fully qualified name or simple name).

#### `#replace_field(name, options)`
Replaces or adds a form field. Options include:
- `rect`: Array of [x, y, width, height] coordinates
- `value`: Default value for the field
- `page`: Page number to add the field to (default: 1)

#### `#write_to_string_io`
Returns a StringIO object containing the modified PDF.

### Field Object

Each field returned by `#list_fields` has the following attributes:
- `fqn`: Fully qualified name of the field
- `name`: Simple name of the field
- `type`: Field type (e.g., "/Tx" for text fields)
- `ref`: Object reference
- `dict`: Raw field dictionary
- `kids_count`: Number of child fields

## Example

See `example.rb` for a complete demonstration of all features.

## Architecture

AcroThat is built as a minimal PDF engine with the following components:

- **Parser**: Extracts PDF objects and parses basic structures
- **Xref**: Handles cross-reference tables and object offsets
- **Document**: Main orchestration class
- **AcroForm**: Handles form field operations
- **Utils**: Utility functions for PDF string handling

## Limitations

This is a minimal implementation focused on AcroForm manipulation. It does not support:

- Complex PDF features (images, fonts, etc.)
- Incremental updates
- Compression/decompression
- Full PDF rendering

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rspec` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).