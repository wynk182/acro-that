# frozen_string_literal: true

module AcroThat
  # Public API surface for your gem.
  #
  # Goals:
  #  - list_fields: enumerate all AcroForm fields (works even when inside ObjStm)
  #  - update_field: set /V (and /AS for checkbox/radio widgets) by REDEFINING the field object
  #  - remove_field: remove field from the root /Fields array (true widget cleanup is out-of-scope here)
  #  - write: append incremental update (no full rewrite). Existing object streams are NOT modified.
  #
  # Implementation notes:
  #  - We never rewrite existing bytes; we only append new/updated objects + xref + trailer (/Prev chains revisions).
  #  - If the field originally lived inside an ObjStm, we *redefine the same object number* as a standalone object.
  #  - We avoid changing object numbers to keep parent references stable.
  class Document
    attr_reader :path

    # Flatten a PDF to remove incremental updates (pure Ruby implementation)
    # This consolidates all incremental updates into a single, clean PDF structure
    # Modeled after HexaPDF's optimization approach
    # Returns the output path
    def self.flatten_pdf(input_path, output_path = nil)
      output = new(input_path).flatten

      if output_path
        File.binwrite(output_path, output)
        return output_path
      else
        return new(StringIO.new(output))
      end
    end

    def initialize(path_or_io)
      @path = path_or_io.is_a?(String) ? path_or_io : nil
      @raw = case path_or_io
             when String then File.binread(path_or_io)
             else path_or_io.binmode
                  path_or_io.read
             end
      @resolver = AcroThat::ObjectResolver.new(@raw)
      @patches = [] # [{ref:[num,gen], body:String}] to be appended incrementally
    end

    # Flatten this document instance to remove incremental updates
    # Returns a new Document instance with the flattened PDF
    def flatten
      # Get essential references
      root_ref = @resolver.root_ref
      raise "Cannot flatten: no /Root found" unless root_ref

      # Collect all in-use objects with their resolved bodies
      objects = []
      @resolver.each_object do |ref, body|
        objects << { ref: ref, body: body } if body
      end

      # Sort by object number for canonical output
      objects.sort_by! { |obj| obj[:ref][0] }

      # Build the flattened PDF (similar to HexaPDF's approach)
      writer = PDFWriter.new
      writer.write_header

      # Write all objects and track their offsets
      objects.each do |obj|
        writer.write_object(obj[:ref], obj[:body])
      end

      # Write xref table
      writer.write_xref

      # Extract Info reference if present
      trailer_dict = @resolver.trailer_dict
      info_ref = nil
      if trailer_dict =~ %r{/Info\s+(\d+)\s+(\d+)\s+R}
        info_ref = [::Regexp.last_match(1).to_i, ::Regexp.last_match(2).to_i]
      end

      # Write trailer
      max_obj_num = objects.map { |obj| obj[:ref][0] }.max || 0
      writer.write_trailer(max_obj_num + 1, root_ref, info_ref)

      writer.output
    end

    # Flatten this document instance in-place (mutates the current instance)
    # Updates @raw, @resolver, and @path with the flattened PDF
    # Returns self for method chaining
    def flatten!
      # Create flattened PDF content
      flattened_content = flatten

      # Update instance variables
      @raw = flattened_content
      @resolver = AcroThat::ObjectResolver.new(flattened_content)
      @patches = [] # Clear any pending patches

      self
    end

    # Return an array of Field(name, value, type, ref)
    def list_fields
      fields = []
      field_widgets = {} # Track widgets by their parent field ref
      widgets_by_name = {} # Track widgets by field name (for cases without /Parent)

      # Helper to check if a body is a widget annotation (handles /Subtype/Widget or /Subtype /Widget)
      is_widget = lambda do |b|
        return false unless b

        b.include?("/Subtype") && b.include?("/Widget") && b =~ %r{/Subtype\s*/Widget}
      end

      # First pass: Collect widgets and their positions
      @resolver.each_object do |ref, body|
        next unless is_widget.call(body)

        # Extract position from widget
        rect_tok = DictScan.value_token_after("/Rect", body)
        next unless rect_tok && rect_tok.start_with?("[")

        # Parse [x y x+width y+height] format
        rect_values = rect_tok.scan(/[-+]?\d*\.?\d+/).map(&:to_f)
        if rect_values.length == 4
          x, y, x2, y2 = rect_values
          width = x2 - x
          height = y2 - y

          # Find which page this widget is on by checking /P reference directly in body
          # (value_token_after may not return full reference tokens)
          page_num = nil
          if body =~ %r{/P\s+(\d+)\s+(\d+)\s+R}
            page_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
            page_num = find_page_number_for_ref(page_ref)
          end

          widget_info = {
            x: x, y: y, width: width, height: height, page: page_num
          }

          # Find parent field reference by matching directly in body
          # (value_token_after may not return full reference tokens)
          if body =~ %r{/Parent\s+(\d+)\s+(\d+)\s+R}
            parent_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]

            # Store widget info by parent field ref
            field_widgets[parent_ref] ||= []
            field_widgets[parent_ref] << widget_info
          end

          # Also track by field name (from /T) in case /Parent is missing
          if body.include?("/T")
            t_tok = DictScan.value_token_after("/T", body)
            if t_tok
              widget_name = DictScan.decode_pdf_string(t_tok)
              if widget_name && !widget_name.empty?
                widgets_by_name[widget_name] ||= []
                widgets_by_name[widget_name] << widget_info
              end
            end
          end
        end

        # Second pass: Collect fields and match with widget positions
        next unless body&.include?("/T")

        # Helper to check if this looks like a field (handles /Subtype/Widget or /Subtype /Widget)
        is_widget_field = body.include?("/Subtype") && body.include?("/Widget") && body =~ %r{/Subtype\s*/Widget}
        hint = body.include?("/FT") || is_widget_field || body.include?("/Kids") || body.include?("/Parent")
        next unless hint

        t_tok = DictScan.value_token_after("/T", body)
        next unless t_tok

        name = DictScan.decode_pdf_string(t_tok)
        next if name.nil? || name.empty? # Skip fields with empty names (deleted fields)

        v_tok = body.include?("/V") ? DictScan.value_token_after("/V", body) : nil
        value = v_tok && v_tok != "<<" ? DictScan.decode_pdf_string(v_tok) : nil

        ft_tok = body.include?("/FT") ? DictScan.value_token_after("/FT", body) : nil
        type = ft_tok

        # Check if this is a widget (flat structure) or a field object
        position = {}
        # Check if this is a widget annotation (handles /Subtype/Widget or /Subtype /Widget)
        is_widget_annot = body.include?("/Subtype") && body.include?("/Widget") && body =~ %r{/Subtype\s*/Widget}
        if is_widget_annot
          # Widget annotation - extract position directly
          rect_tok = DictScan.value_token_after("/Rect", body)
          if rect_tok && rect_tok.start_with?("[")
            rect_values = rect_tok.scan(/[-+]?\d*\.?\d+/).map(&:to_f)
            if rect_values.length == 4
              x, y, x2, y2 = rect_values
              position = { x: x, y: y, width: x2 - x, height: y2 - y }

              # Try to find page number by matching /P reference directly in body
              # (value_token_after may not return full reference tokens)
              if body =~ %r{/P\s+(\d+)\s+(\d+)\s+R}
                page_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
                position[:page] = find_page_number_for_ref(page_ref)
              end
            end
          end
        elsif field_widgets[ref]
          # Field object with widget children - use first widget's position
          widget_info = field_widgets[ref].first
          position = {
            x: widget_info[:x],
            y: widget_info[:y],
            width: widget_info[:width],
            height: widget_info[:height],
            page: widget_info[:page]
          }
        elsif widgets_by_name[name]
          # Try to find widgets by field name (fallback when /Parent is missing)
          widget_info = widgets_by_name[name].first
          position = {
            x: widget_info[:x],
            y: widget_info[:y],
            width: widget_info[:width],
            height: widget_info[:height],
            page: widget_info[:page]
          }
        end

        fields << Field.new(name, value, type, ref, self, position)
      end

      # Last-resort fallback if xref parsing missed something
      if fields.empty?
        stripped = DictScan.strip_stream_bodies(@raw)
        DictScan.each_dictionary(stripped) do |dict_src|
          next unless dict_src.include?("/T")

          # Helper to check if this looks like a field (handles /Subtype/Widget or /Subtype /Widget)
          is_widget_field_fallback = dict_src.include?("/Subtype") && dict_src.include?("/Widget") && dict_src =~ %r{/Subtype\s*/Widget}
          hint = dict_src.include?("/FT") || is_widget_field_fallback || dict_src.include?("/Kids") || dict_src.include?("/Parent")
          next unless hint

          t_tok = DictScan.value_token_after("/T", dict_src)
          next unless t_tok

          name = DictScan.decode_pdf_string(t_tok)
          next if name.nil? || name.empty? # Skip fields with empty names (deleted fields)

          v_tok = dict_src.include?("/V") ? DictScan.value_token_after("/V", dict_src) : nil
          value = v_tok && v_tok != "<<" ? DictScan.decode_pdf_string(v_tok) : nil
          ft_tok = dict_src.include?("/FT") ? DictScan.value_token_after("/FT", dict_src) : nil
          fields << Field.new(name, value, ft_tok, [-1, 0], self) # unknown ref in fallback
        end
      end

      # Uniq by name, prefer the lowest ref number (stable-ish)
      fields.group_by(&:name).values.map { |arr| arr.min_by { |f| f.ref[0] } }
    end

    # Add a new field to the AcroForm /Fields array.
    # Options should include:
    #   - value: default value for the field
    #   - type: field type (e.g., "/Tx" for text, "/Btn" for button, "/Ch" for choice)
    #   - x, y, width, height: positioning coordinates
    #   - page: page number to add the field to (default: 1)
    # Returns the Field instance if the field was added, nil otherwise.
    def add_field(name, options = {})
      action = Actions::AddField.new(self, name, options)
      result = action.call

      if result
        # Extract position from options
        position = {
          x: options[:x] || 100,
          y: options[:y] || 500,
          width: options[:width] || 100,
          height: options[:height] || 20,
          page: options[:page] || 1
        }

        # Get action attributes before write (they're already set during call)
        field_obj_num = action.field_obj_num
        field_type = action.field_type
        field_value = action.field_value

        # Apply the changes immediately to update @raw and @resolver
        write

        # Create and return the Field instance with position information
        Field.new(name, field_value, field_type, [field_obj_num, 0], self, position)
      end
    end

    # Update field by *name* (case-sensitive), setting /V and, if necessary, /AS on widgets.
    # Optionally rename the field by providing new_name.
    # Returns true if the field was found and queued for write.
    def update_field(name, new_value, new_name: nil)
      field = list_fields.find { |f| f.name == name }
      return false unless field

      field.update(new_value, new_name: new_name)
    end

    # Remove field by name from the AcroForm /Fields array and mark the field object as deleted.
    # Note: This does not purge page /Annots widgets (non-trivial); most viewers will hide the field
    # once it is no longer in the field tree.
    # Can accept either a Field instance or a field name (String).
    # Returns true if the field was removed.
    def remove_field(fld)
      field = fld.is_a?(Field) ? fld : list_fields.find { |f| f.name == fld }
      return false unless field

      field.remove
    end

    # Write out with an incremental update.
    # path_out: String path; if nil, returns the bytes.
    def write(path_out = nil, flatten: false)
      # Deduplicate patches: keep only the last patch for each object ref
      # (multiple operations on the same object should use the final state)
      deduped_patches = @patches.reverse.uniq { |p| p[:ref] }.reverse

      writer = AcroThat::IncrementalWriter.new(@raw, deduped_patches)
      @raw = writer.render

      # Reset patches since they're now applied
      @patches = []

      # Update instance state with the incremental update
      @resolver = AcroThat::ObjectResolver.new(@raw)

      # If flatten requested, consolidate incremental updates into a clean PDF
      if flatten
        flatten! # Updates @raw in place
      end

      if path_out
        File.binwrite(path_out, @raw)
        return true
      else
        return @raw
      end
    end

    private

    # Find the page number (1-indexed) for a given page object reference
    def find_page_number_for_ref(page_ref)
      page_objects = []
      @resolver.each_object do |ref, body|
        next unless body&.include?("/Type /Page")

        page_objects << ref
      end

      return nil if page_objects.empty?

      # Find index of this page ref
      page_index = page_objects.index(page_ref)
      return nil unless page_index

      page_index + 1 # Convert to 1-indexed page number
    end

    def next_object_number
      # Find the highest object number in the document and return the next one
      max_obj_num = 0
      @resolver.each_object do |ref, _|
        max_obj_num = [max_obj_num, ref[0]].max
      end
      max_obj_num + 1
    end

    def next_fresh_object_number
      max_obj_num = 0
      @resolver.each_object do |ref, _|
        max_obj_num = [max_obj_num, ref[0]].max
      end
      @patches.each do |p|
        max_obj_num = [max_obj_num, p[:ref][0]].max
      end
      max_obj_num + 1
    end

    def acroform_ref
      # trailer -> /Root -> Catalog -> /AcroForm
      root_ref = @resolver.root_ref
      return nil unless root_ref

      cat_body = @resolver.object_body(root_ref)

      return nil unless cat_body =~ %r{/AcroForm\s+(\d+)\s+(\d+)\s+R}

      [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
    end
  end
end
