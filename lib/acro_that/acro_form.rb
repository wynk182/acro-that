# frozen_string_literal: true

module AcroThat
  # Enhanced AcroForm handler that works with both regular objects and object streams
  class AcroForm
    attr_reader :resolver, :acro_form_ref, :acro_form_dict

    def initialize(resolver)
      @resolver = resolver
      @acro_form_ref = find_acro_form_ref
      @acro_form_dict = @acro_form_ref ? resolve_dict(@acro_form_ref) : nil
    end

    # List all form fields recursively
    def fields
      fields = []

      # Check if AcroForm dictionary exists
      unless @acro_form_dict
        puts "Warning: AcroForm dictionary not found"
        return fields
      end

      fields_ref = @acro_form_dict["/Fields"]
      return fields unless fields_ref

      fields_array = resolve_array(fields_ref)
      return fields unless fields_array.is_a?(Array)

      fields_array.each do |field_ref|
        field_dict = resolve_dict(field_ref)
        next unless field_dict.is_a?(Hash)

        # Collect field info
        field_info = {
          ref: field_ref,
          dict: field_dict,
          name: field_dict["/T"],
          type: field_dict["/FT"],
          value: field_dict["/V"],
          fqn: build_field_name(field_dict),
          kids_count: 0,
          widget_refs: []
        }

        # Count kids and collect widget refs
        kids_ref = field_dict["/Kids"]
        if kids_ref
          kids_array = resolve_array(kids_ref)
          if kids_array.is_a?(Array)
            field_info[:kids_count] = kids_array.length
            field_info[:widget_refs] = kids_array.select do |kid_ref|
              kid_dict = resolve_dict(kid_ref)
              kid_dict.is_a?(Hash) && kid_dict["/Subtype"] == "/Widget"
            end
          end
        end

        fields << field_info
      end

      fields
    end

    # Set field value and return patches
    def set_value(name, new_value)
      patches = []

      # Find the field
      field_info = find_field_by_name(name)
      return patches unless field_info

      field_ref = field_info[:ref]
      field_dict = field_info[:dict]

      # Determine the new value format based on field type
      formatted_value = format_field_value(field_dict["/FT"], new_value)

      # Update the field dictionary
      updated_dict = field_dict.dup
      updated_dict["/V"] = formatted_value

      # For checkboxes/radios, also set /AS
      if ["/Btn", "/Ch"].include?(field_dict["/FT"])
        updated_dict["/AS"] = if [true, "true", "/Yes"].include?(new_value)
                                "/Yes"
                              else
                                "/Off"
                              end
      end

      # Serialize the updated dictionary
      new_body = serialize_dictionary(updated_dict)

      # Create patch for field replacement
      patches << {
        type: :replace_object,
        obj_num: field_ref[:num],
        obj_gen: field_ref[:gen],
        new_body: new_body
      }

      # Set NeedAppearances flag on AcroForm
      if @acro_form_dict
        updated_acro_form = @acro_form_dict.dup
        updated_acro_form["/NeedAppearances"] = true

        acro_form_body = serialize_dictionary(updated_acro_form)
        patches << {
          type: :replace_object,
          obj_num: @acro_form_ref[:num],
          obj_gen: @acro_form_ref[:gen],
          new_body: acro_form_body
        }
      end

      patches
    end

    # Remove field and return patches
    def remove_field(name)
      patches = []

      # Find the field
      field_info = find_field_by_name(name)
      return patches unless field_info

      field_ref = field_info[:ref]
      field_info[:dict]

      # Remove field from /Fields array
      fields_ref = @acro_form_dict["/Fields"]
      if fields_ref
        fields_array = resolve_array(fields_ref)
        if fields_array.is_a?(Array)
          updated_fields = fields_array.reject { |ref| ref == field_ref }

          # Create patch for updated fields array
          new_fields_body = serialize_array(updated_fields)
          patches << {
            type: :replace_object,
            obj_num: fields_ref[:num],
            obj_gen: fields_ref[:gen],
            new_body: new_fields_body
          }
        end
      end

      # Remove field's widget annotations from pages
      widget_patches = remove_field_widgets(field_ref)
      patches.concat(widget_patches)

      patches
    end

    private

    def find_acro_form_ref
      # Get root reference from trailer
      root_ref = @resolver.trailer["/Root"]
      return nil unless root_ref

      # Get catalog
      catalog_dict = resolve_dict(root_ref)
      return nil unless catalog_dict.is_a?(Hash)

      # Get AcroForm reference
      catalog_dict["/AcroForm"]
    end

    def resolve_dict(ref)
      return nil unless ref.is_a?(Hash) && ref[:type] == :ref

      obj_data = @resolver.object(ref)
      return nil unless obj_data

      # Parse the dictionary from the object body
      parse_dictionary_from_body(obj_data[:body])
    end

    def resolve_array(ref)
      return nil unless ref.is_a?(Hash) && ref[:type] == :ref

      obj_data = @resolver.object(ref)
      return nil unless obj_data

      # Parse the array from the object body
      parse_array_from_body(obj_data[:body])
    end

    def parse_dictionary_from_body(body)
      dict = {}

      # Use DictScan to find dictionaries
      DictScan.each_dictionary(body) do |dict_src|
        # Extract key-value pairs
        dict_src.scan(%r{/([A-Za-z][A-Za-z0-9]*)\s+([^/]+?)(?=\s*/[A-Za-z]|\s*>>|\s*$)}mn) do |key, value|
          key = "/#{key}"
          value = value.strip

          # Handle references
          if value.match(/^\d+\s+\d+\s+R$/)
            num, gen = value.split.map(&:to_i)
            dict[key] = { type: :ref, num: num, gen: gen }
          elsif value.start_with?("/")
            dict[key] = value
          else
            dict[key] = parse_value(value)
          end
        end
      end

      dict
    end

    def parse_array_from_body(body)
      # Find array content between [ and ]
      array_match = body.match(/\[(.*?)\]/mn)
      return [] unless array_match

      array_content = array_match[1]
      return [] if array_content.strip.empty?

      # Parse array elements
      elements = []
      current_element = ""
      depth = 0

      array_content.each_char do |char|
        case char
        when "["
          depth += 1
          current_element += char
        when "]"
          depth -= 1
          current_element += char
        when /\s/
          if depth.zero? && !current_element.strip.empty?
            elements << parse_value(current_element.strip)
            current_element = ""
          else
            current_element += char
          end
        else
          current_element += char
        end
      end

      elements << parse_value(current_element.strip) unless current_element.strip.empty?
      elements
    end

    def parse_value(str)
      str = str.strip

      case str
      when /^<<.*>>$/m
        # Dictionary
        parse_dictionary_from_body(str)
      when /^\[.*\]$/m
        # Array
        parse_array_from_body(str)
      when /^\(.*\)$/m
        # String literal
        DictScan.decode_pdf_string(str)
      when /^(\d+)\s+(\d+)\s+R$/
        # Indirect reference
        { type: :ref, num: ::Regexp.last_match(1).to_i, gen: ::Regexp.last_match(2).to_i }
      when %r{^/[A-Za-z][A-Za-z0-9]*$}
        # Name
        str
      when /^-?\d+\.?\d*$/
        # Number
        str.include?(".") ? str.to_f : str.to_i
      when /^(true|false)$/
        # Boolean
        str == "true"
      when /^null$/
        # Null
        nil
      else
        # Treat as string if nothing else matches
        str
      end
    end

    def find_field_by_name(name)
      fields_array = resolve_array(@acro_form_dict["/Fields"])
      return nil unless fields_array.is_a?(Array)

      fields_array.each do |field_ref|
        field_dict = resolve_dict(field_ref)
        next unless field_dict.is_a?(Hash)

        field_name = build_field_name(field_dict)
        if field_name == name || field_dict["/T"] == name
          return { ref: field_ref, dict: field_dict }
        end
      end

      nil
    end

    def build_field_name(field_dict)
      name = field_dict["/T"]
      return name if name.nil? || name.empty?

      # Handle hierarchical field names
      parent_ref = field_dict["/Parent"]
      if parent_ref
        parent_dict = resolve_dict(parent_ref)
        if parent_dict.is_a?(Hash)
          parent_name = build_field_name(parent_dict)
          return "#{parent_name}.#{name}" if parent_name && !parent_name.empty?
        end
      end

      name
    end

    def format_field_value(field_type, value)
      case field_type
      when "/Tx", "/Sig" # Text fields
        if value.is_a?(String) && value.include?("\\")
          # Already escaped
          "(#{value})"
        else
          Utils.pdf_text_string(value.to_s)
        end
      when "/Btn", "/Ch" # Button/Checkbox fields
        if [true, "true", "/Yes"].include?(value)
          "/Yes"
        else
          "/Off"
        end
      else
        Utils.pdf_text_string(value.to_s)
      end
    end

    def serialize_dictionary(dict)
      lines = ["<<"]

      dict.each do |key, value|
        lines << "  #{key} #{serialize_value(value)}"
      end

      lines << ">>"
      lines.join("\n")
    end

    def serialize_array(array)
      elements = array.map { |value| serialize_value(value) }
      "[#{elements.join(' ')}]"
    end

    def serialize_value(value)
      case value
      when Hash
        if value[:type] == :ref
          "#{value[:num]} #{value[:gen]} R"
        else
          serialize_dictionary(value)
        end
      when Array
        serialize_array(value)
      when String
        if value.start_with?("/")
          value
        else
          Utils.pdf_text_string(value)
        end
      when Numeric
        value.to_s
      when true, false
        value.to_s
      when nil
        "null"
      else
        value.to_s
      end
    end

    def remove_field_widgets(field_ref)
      patches = []

      # Find pages that reference this field
      @resolver.xref_entries.each do |(obj_num, obj_gen), entry|
        next unless entry[:type] == :in_file

        obj_data = @resolver.object({ num: obj_num, gen: obj_gen })
        next unless obj_data

        # Check if this is a page object
        page_dict = parse_dictionary_from_body(obj_data[:body])
        next unless page_dict["/Type"] == "/Page"

        annots_ref = page_dict["/Annots"]
        next unless annots_ref

        annots_array = resolve_array(annots_ref)
        next unless annots_array.is_a?(Array)

        # Remove field reference from annotations
        updated_annots = annots_array.reject do |annot_ref|
          annot_dict = resolve_dict(annot_ref)
          annot_dict.is_a?(Hash) && annot_dict["/Parent"] == field_ref
        end

        next unless updated_annots.length != annots_array.length

        # Create patch for updated annotations array
        new_annots_body = serialize_array(updated_annots)
        patches << {
          type: :replace_object,
          obj_num: annots_ref[:num],
          obj_gen: annots_ref[:gen],
          new_body: new_annots_body
        }
      end

      patches
    end
  end
end
