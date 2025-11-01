# frozen_string_literal: true

module AcroThat
  module Actions
    # Action to add a new field to a PDF document
    class AddField
      include Base

      attr_reader :field_obj_num, :field_type, :field_value

      def initialize(document, name, options = {})
        @document = document
        @name = name
        @options = options
        @metadata = options[:metadata] || {}
      end

      def call
        x = @options[:x] || 100
        y = @options[:y] || 500
        width = @options[:width] || 100
        height = @options[:height] || 20
        page_num = @options[:page] || 1

        # Normalize field type: accept symbols or strings, convert to PDF format
        type_input = @options[:type] || "/Tx"
        @field_type = case type_input
                      when :text, "text", "/Tx", "/tx"
                        "/Tx"
                      when :button, "button", "/Btn", "/btn"
                        "/Btn"
                      when :radio, "radio"
                        "/Btn"
                      when :checkbox, "checkbox"
                        "/Btn"
                      when :choice, "choice", "/Ch", "/ch"
                        "/Ch"
                      when :signature, "signature", "/Sig", "/sig"
                        "/Sig"
                      else
                        type_input.to_s # Use as-is if it's already in PDF format
                      end
        @field_value = @options[:value] || ""

        # Auto-set radio button flags if type is :radio and flags not explicitly set
        # Radio button flags: Radio (bit 15 = 32768) + NoToggleToOff (bit 14 = 16384) = 49152
        if [:radio, "radio"].include?(type_input) && !(@metadata[:Ff] || @metadata["Ff"])
          @metadata[:Ff] = 49_152
        end

        # Create a proper field dictionary + a widget annotation that references it via /Parent
        @field_obj_num = next_fresh_object_number
        widget_obj_num = @field_obj_num + 1

        field_body = create_field_dictionary(@field_value, @field_type)

        # Find the page ref for /P on widget (must happen before we create patches)
        page_ref = find_page_ref(page_num)

        # Create widget with page reference
        widget_body = create_widget_annotation_with_parent(widget_obj_num, [@field_obj_num, 0], page_ref, x, y, width,
                                                           height, @field_type, @field_value)

        # Queue objects
        @document.instance_variable_get(:@patches) << { ref: [@field_obj_num, 0], body: field_body }
        @document.instance_variable_get(:@patches) << { ref: [widget_obj_num, 0], body: widget_body }

        # Add field reference (not widget) to AcroForm /Fields AND ensure defaults in ONE patch
        add_field_to_acroform_with_defaults(@field_obj_num)

        # Add widget to the target page's /Annots
        add_widget_to_page(widget_obj_num, page_num)

        # If this is a signature field with image data, add the signature appearance
        if @field_type == "/Sig" && @field_value && !@field_value.empty?
          image_data = @field_value
          # Check if value looks like base64 image data or data URI (same logic as update_field)
          if image_data.is_a?(String) && (image_data.start_with?("data:image/") || (image_data.length > 50 && image_data.match?(%r{^[A-Za-z0-9+/]*={0,2}$})))
            field_ref = [@field_obj_num, 0]
            # Try adding signature appearance - use width and height from options
            action = Actions::AddSignatureAppearance.new(@document, field_ref, image_data, width: width, height: height)
            # NOTE: We don't fail if appearance addition fails - field was still created successfully
            action.call
          end
        end

        # If this is a checkbox (button field that's not a radio button), add appearance dictionaries
        # Button fields can be checkboxes or radio buttons:
        # - Radio buttons have Radio flag (bit 15 = 32768) set
        # - Checkboxes don't have Radio flag set
        is_checkbox = false
        if @field_type == "/Btn"
          field_flags = (@metadata[:Ff] || @metadata["Ff"] || 0).to_i
          is_radio = field_flags.anybits?(32_768) || [:radio, "radio"].include?(type_input)
          is_checkbox = !is_radio
        end

        if is_checkbox
          add_checkbox_appearance(widget_obj_num, x, y, width, height)
        end

        true
      end

      private

      def create_field_dictionary(value, type)
        dict = "<<\n"
        dict += "  /FT #{type}\n"
        dict += "  /T #{DictScan.encode_pdf_string(@name)}\n"

        # Apply /Ff from metadata, or use default 0
        # Note: Radio button flags should already be set in metadata during type normalization
        field_flags = @metadata[:Ff] || @metadata["Ff"] || 0
        dict += "  /Ff #{field_flags}\n"

        dict += "  /DA (/Helv 0 Tf 0 g)\n"

        # For signature fields with image data, don't set /V (appearance stream will be added separately)
        # For checkboxes/radio buttons, set /V to normalized value (Yes/Off) - macOS Preview needs this
        # For other fields, set /V normally
        should_set_value = if type == "/Sig" && value && !value.empty?
                             # Check if value looks like image data
                             !(value.is_a?(String) && (value.start_with?("data:image/") || (value.length > 50 && value.match?(%r{^[A-Za-z0-9+/]*={0,2}$}))))
                           else
                             true
                           end

        # For button fields (checkboxes/radio), normalize value to "Yes" or "Off"
        normalized_field_value = if type == "/Btn" && value
                                   # Accept "Yes", "/Yes" (PDF name format), true (boolean), or "true" (string)
                                   value_str = value.to_s
                                   is_checked = ["Yes", "/Yes", "true"].include?(value_str) || value == true
                                   is_checked ? "Yes" : "Off"
                                 else
                                   value
                                 end

        dict += "  /V #{DictScan.encode_pdf_string(normalized_field_value)}\n" if should_set_value && normalized_field_value && !normalized_field_value.to_s.empty?

        # Apply other metadata entries (excluding Ff which we handled above)
        @metadata.each do |key, val|
          next if [:Ff, "Ff"].include?(key) # Already handled above

          pdf_key = DictScan.format_pdf_key(key)
          pdf_value = DictScan.format_pdf_value(val)
          dict += "  #{pdf_key} #{pdf_value}\n"
        end

        dict += ">>"
        dict
      end

      def create_widget_annotation_with_parent(_widget_obj_num, parent_ref, page_ref, x, y, width, height, type, value)
        rect_array = "[#{x} #{y} #{x + width} #{y + height}]"
        widget = "<<\n"
        widget += "  /Type /Annot\n"
        widget += "  /Subtype /Widget\n"
        widget += "  /Parent #{parent_ref[0]} #{parent_ref[1]} R\n"
        widget += "  /P #{page_ref[0]} #{page_ref[1]} R\n" if page_ref
        widget += "  /FT #{type}\n"
        widget += "  /Rect #{rect_array}\n"
        widget += "  /F 4\n"
        widget += "  /DA (/Helv 0 Tf 0 g)\n"

        # For checkboxes, /V is set to "Yes" or "Off" and /AS is set accordingly
        # For signature fields with image data, don't set /V (appearance stream will be added separately)
        # For other fields or non-image signature values, set /V normally
        should_set_value = if type == "/Sig" && value && !value.empty?
                             # Check if value looks like image data
                             !(value.is_a?(String) && (value.start_with?("data:image/") || (value.length > 50 && value.match?(%r{^[A-Za-z0-9+/]*={0,2}$}))))
                           elsif type == "/Btn"
                             # For button fields (checkboxes), set /V to "Yes" or "Off"
                             # This will be handled by checkbox appearance code, but we set it here for consistency
                             true
                           else
                             true
                           end

        # For checkboxes, set /V to "Yes" or empty/Off
        if type == "/Btn" && should_set_value
          # Checkbox value should be "Yes" if checked, otherwise empty or "Off"
          # Accept "Yes", "/Yes" (PDF name format), true (boolean), or "true" (string)
          value_str = value.to_s
          is_checked = ["Yes", "/Yes", "true"].include?(value_str) || value == true
          checkbox_value = is_checked ? "Yes" : "Off"
          widget += "  /V #{DictScan.encode_pdf_string(checkbox_value)}\n"
        elsif should_set_value && value && !value.empty?
          widget += "  /V #{DictScan.encode_pdf_string(value)}\n"
        end

        # Apply metadata entries that are valid for widgets
        # Common widget properties: /Q (alignment), /Ff (field flags), /BS (border style), etc.
        @metadata.each do |key, val|
          pdf_key = DictScan.format_pdf_key(key)
          pdf_value = DictScan.format_pdf_value(val)
          # Only add if not already present (we've added /F above, /V above if value exists)
          next if ["/F", "/V"].include?(pdf_key)

          widget += "  #{pdf_key} #{pdf_value}\n"
        end

        widget += ">>"
        widget
      end

      def add_field_to_acroform_with_defaults(field_obj_num)
        af_ref = acroform_ref
        return false unless af_ref

        af_body = get_object_body_with_patch(af_ref)

        patched = af_body.dup

        # Step 1: Add field to /Fields array
        fields_array_ref = DictScan.value_token_after("/Fields", patched)

        if fields_array_ref && fields_array_ref =~ /\A(\d+)\s+(\d+)\s+R/
          # Reference case: /Fields points to a separate array object
          arr_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
          arr_body = get_object_body_with_patch(arr_ref)
          new_body = DictScan.add_ref_to_array(arr_body, [field_obj_num, 0])
          apply_patch(arr_ref, new_body, arr_body)
        elsif patched.include?("/Fields")
          # Inline array case: use DictScan utility
          patched = DictScan.add_ref_to_inline_array(patched, "/Fields", [field_obj_num, 0])
        else
          # No /Fields exists - add it with the field reference
          patched = DictScan.upsert_key_value(patched, "/Fields", "[#{field_obj_num} 0 R]")
        end

        # Step 2: Ensure /NeedAppearances true
        unless patched.include?("/NeedAppearances")
          patched = DictScan.upsert_key_value(patched, "/NeedAppearances", "true")
        end

        # Step 2.5: Remove /XFA if present (prevents XFA detection warnings in viewers like Master PDF)
        # We're creating AcroForms, not XFA forms, so remove /XFA if it exists
        if patched.include?("/XFA")
          xfa_pattern = %r{/XFA(?=[\s(<\[/])}
          if patched.match(xfa_pattern)
            # Try to get the value token to determine what we're removing
            xfa_value = DictScan.value_token_after("/XFA", patched)
            if xfa_value
              # Remove /XFA by replacing it with an empty string
              # We'll use a simple approach: find the key and remove it with its value
              xfa_match = patched.match(xfa_pattern)
              if xfa_match
                # Find the start and end of /XFA and its value
                key_start = xfa_match.begin(0)
                # Skip /XFA key
                value_start = xfa_match.end(0)
                value_start += 1 while value_start < patched.length && patched[value_start] =~ /\s/
                # Use value_token_after to get the complete value token
                # We already have xfa_value, so calculate its end
                value_end = value_start + xfa_value.length
                # Skip trailing whitespace
                value_end += 1 while value_end < patched.length && patched[value_end] =~ /\s/
                # Remove /XFA and its value
                before = patched[0...key_start]
                # Remove any whitespace before /XFA too (but not the opening <<)
                before = before.rstrip
                after = patched[value_end..]
                patched = "#{before} #{after.lstrip}".strip
                # Clean up any double spaces
                patched = patched.gsub(/\s+/, " ")
              end
            end
          end
        end

        # Step 3: Ensure /DR /Font has /Helv mapping
        unless patched.include?("/DR") && patched.include?("/Helv")
          font_obj_num = next_fresh_object_number
          font_body = "<<\n  /Type /Font\n  /Subtype /Type1\n  /BaseFont /Helvetica\n>>"
          patches << { ref: [font_obj_num, 0], body: font_body }

          if patched.include?("/DR")
            # /DR exists - try to add /Font if it doesn't exist
            dr_tok = DictScan.value_token_after("/DR", patched)
            if dr_tok && dr_tok.start_with?("<<")
              # Check if /Font already exists in /DR
              unless dr_tok.include?("/Font")
                # Add /Font to existing /DR dictionary
                new_dr_tok = dr_tok.chomp(">>") + "  /Font << /Helv #{font_obj_num} 0 R >>\n>>"
                patched = patched.sub(dr_tok) { |_| new_dr_tok }
              end
            else
              # /DR exists but isn't a dictionary - replace it
              patched = DictScan.replace_key_value(patched, "/DR", "<< /Font << /Helv #{font_obj_num} 0 R >> >>")
            end
          else
            # No /DR exists - add it
            patched = DictScan.upsert_key_value(patched, "/DR", "<< /Font << /Helv #{font_obj_num} 0 R >> >>")
          end
        end

        apply_patch(af_ref, patched, af_body)
        true
      end

      def find_page_ref(page_num)
        # Use Document's unified page-finding method
        find_page_by_number(page_num)
      end

      def add_widget_to_page(widget_obj_num, page_num)
        # Find the specific page using the same logic as find_page_ref
        target_page_ref = find_page_ref(page_num)
        return false unless target_page_ref

        page_body = get_object_body_with_patch(target_page_ref)

        # Use DictScan utility to safely add reference to /Annots array
        new_body = if page_body =~ %r{/Annots\s*\[(.*?)\]}m
                     # Inline array - add to it
                     result = DictScan.add_ref_to_inline_array(page_body, "/Annots", [widget_obj_num, 0])
                     if result && result != page_body
                       result
                     else
                       # Fallback: use string manipulation
                       annots_array = ::Regexp.last_match(1)
                       ref_token = "#{widget_obj_num} 0 R"
                       new_annots = if annots_array.strip.empty?
                                      "[#{ref_token}]"
                                    else
                                      "[#{annots_array} #{ref_token}]"
                                    end
                       page_body.sub(%r{/Annots\s*\[.*?\]}, "/Annots #{new_annots}")
                     end
                   elsif page_body =~ %r{/Annots\s+(\d+)\s+(\d+)\s+R}
                     # Indirect array reference - need to read and modify the array object
                     annots_array_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
                     annots_array_body = get_object_body_with_patch(annots_array_ref)

                     ref_token = "#{widget_obj_num} 0 R"
                     if annots_array_body
                       new_annots_body = if annots_array_body.strip == "[]"
                                           "[#{ref_token}]"
                                         elsif annots_array_body.strip.start_with?("[") && annots_array_body.strip.end_with?("]")
                                           without_brackets = annots_array_body.strip[1..-2].strip
                                           "[#{without_brackets} #{ref_token}]"
                                         else
                                           "[#{annots_array_body} #{ref_token}]"
                                         end

                       apply_patch(annots_array_ref, new_annots_body, annots_array_body)

                       # Page body doesn't need to change (still references the same array object)
                       page_body
                     else
                       # Array object not found - fallback to creating inline array
                       page_body.sub(%r{/Annots\s+\d+\s+\d+\s+R}, "/Annots [#{ref_token}]")
                     end
                   else
                     # No /Annots exists - add it with the widget reference
                     # Insert /Annots before the closing >> of the dictionary
                     ref_token = "#{widget_obj_num} 0 R"
                     if page_body.include?(">>")
                       # Find the last >> (closing the outermost dictionary) and insert /Annots before it
                       page_body.reverse.sub(">>".reverse, "/Annots [#{ref_token}]>>".reverse).reverse
                     else
                       page_body + " /Annots [#{ref_token}]"
                     end
                   end

        apply_patch(target_page_ref, new_body, page_body) if new_body && new_body != page_body
        true
      end

      def add_checkbox_appearance(widget_obj_num, _x, _y, width, height)
        # Create appearance form XObjects for Yes and Off states
        yes_obj_num = next_fresh_object_number
        off_obj_num = yes_obj_num + 1

        # Create Yes appearance (checked box with checkmark)
        yes_body = create_checkbox_yes_appearance(width, height)
        @document.instance_variable_get(:@patches) << { ref: [yes_obj_num, 0], body: yes_body }

        # Create Off appearance (empty box)
        off_body = create_checkbox_off_appearance(width, height)
        @document.instance_variable_get(:@patches) << { ref: [off_obj_num, 0], body: off_body }

        # Get current widget body and add /AP dictionary
        widget_ref = [widget_obj_num, 0]
        original_widget_body = get_object_body_with_patch(widget_ref)
        widget_body = original_widget_body.dup

        # Create /AP dictionary with Yes and Off appearances
        ap_dict = "<<\n  /N <<\n    /Yes #{yes_obj_num} 0 R\n    /Off #{off_obj_num} 0 R\n  >>\n>>"

        # Add /AP to widget
        if widget_body.include?("/AP")
          # Replace existing /AP
          ap_key_pattern = %r{/AP(?=[\s(<\[/])}
          if widget_body.match(ap_key_pattern)
            widget_body = DictScan.replace_key_value(widget_body, "/AP", ap_dict)
          end
        else
          # Insert /AP before closing >>
          widget_body = DictScan.upsert_key_value(widget_body, "/AP", ap_dict)
        end

        # Set /AS based on the value - use the EXACT same normalization logic as widget creation
        # This ensures consistency between /V and /AS
        # Normalize value: "Yes" if truthy (Yes, "/Yes", true, etc.), otherwise "Off"
        value_str = @field_value.to_s
        is_checked = value_str == "Yes" || value_str == "/Yes" || value_str == "true" || @field_value == true
        normalized_value = is_checked ? "Yes" : "Off"

        # Set /AS to match normalized value (same as what was set for /V in widget creation)
        as_value = if normalized_value == "Yes"
                     "/Yes"
                   else
                     "/Off"
                   end

        widget_body = if widget_body.include?("/AS")
                        DictScan.replace_key_value(widget_body, "/AS", as_value)
                      else
                        DictScan.upsert_key_value(widget_body, "/AS", as_value)
                      end

        apply_patch(widget_ref, widget_body, original_widget_body)
      end

      def create_checkbox_yes_appearance(width, height)
        # Create a form XObject that draws a checked checkbox
        # Box outline + checkmark
        # Scale to match width and height
        # Simple appearance: draw a box and a checkmark
        # For simplicity, use PDF drawing operators
        # Box: rectangle from (0,0) to (width, height)
        # Checkmark: simple path drawing

        # PDF content stream for checked checkbox
        # Draw just the checkmark (no box border)
        border_width = [width * 0.08, height * 0.08].min

        # Calculate checkmark path
        check_x1 = width * 0.25
        check_y1 = height * 0.45
        check_x2 = width * 0.45
        check_y2 = height * 0.25
        check_x3 = width * 0.75
        check_y3 = height * 0.75

        content_stream = "q\n"
        content_stream += "0 0 0 rg\n" # Black color (darker)
        content_stream += "#{border_width} w\n" # Line width
        # Draw checkmark only (no box border)
        content_stream += "#{check_x1} #{check_y1} m\n"
        content_stream += "#{check_x2} #{check_y2} l\n"
        content_stream += "#{check_x3} #{check_y3} l\n"
        content_stream += "S\n" # Stroke
        content_stream += "Q\n"

        build_form_xobject(content_stream, width, height)
      end

      def create_checkbox_off_appearance(width, height)
        # Create a form XObject for unchecked checkbox
        # Empty appearance (no border, no checkmark) - viewer will draw default checkbox

        content_stream = "q\n"
        # Empty appearance for unchecked state
        content_stream += "Q\n"

        build_form_xobject(content_stream, width, height)
      end

      def build_form_xobject(content_stream, width, height)
        # Build a Form XObject dictionary with the given content stream
        dict = "<<\n"
        dict += "  /Type /XObject\n"
        dict += "  /Subtype /Form\n"
        dict += "  /BBox [0 0 #{width} #{height}]\n"
        dict += "  /Length #{content_stream.bytesize}\n"
        dict += ">>\n"
        dict += "stream\n"
        dict += content_stream
        dict += "\nendstream"

        dict
      end
    end
  end
end
