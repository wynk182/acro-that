# frozen_string_literal: true

module AcroThat
  module Actions
    # Action to update a field's value and optionally rename it in a PDF document
    class UpdateField
      def initialize(document, name, new_value, new_name: nil)
        @document = document
        @name = name
        @new_value = new_value
        @new_name = new_name
      end

      def call
        fld = @document.list_fields.find { |f| f.name == @name }
        return false unless fld

        # Check if this is a widget annotation (has /Subtype /Widget) or a field object
        original = resolver.object_body(fld.ref)
        return false unless original

        # Check for existing patch for this field
        existing_patch = patches.find { |p| p[:ref] == fld.ref }
        original = existing_patch[:body] if existing_patch

        # Determine if this is a widget annotation or field object
        is_widget = original.include?("/Subtype /Widget")
        field_ref = fld.ref # Default: the ref we found is the field

        # If this is a widget, we need to also update the parent field object (if it exists)
        # Otherwise, this widget IS the field (flat structure)
        if is_widget
          parent_tok = DictScan.value_token_after("/Parent", original)
          if parent_tok && parent_tok =~ /\A(\d+)\s+(\d+)\s+R/
            field_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
            # Get and update the parent field object
            field_body = resolver.object_body(field_ref)
            if field_body && !field_body.include?("/Subtype /Widget") # Make sure it's actually a field, not another widget
              existing_field_patch = patches.find { |p| p[:ref] == field_ref }
              field_body = existing_field_patch[:body] if existing_field_patch

              new_field_body = patch_field_value_body(field_body, @new_value)
              if new_field_body && new_field_body.include?("<<") && new_field_body.include?(">>")
                patches.reject! { |p| p[:ref] == field_ref }
                patches << { ref: field_ref, body: new_field_body }
              end
            end
          end
        end

        # Update the object we found (widget or field) - always update what we found
        new_body = patch_field_value_body(original, @new_value)

        # Update field name (/T) if requested
        if @new_name && !@new_name.empty?
          new_body = patch_field_name_body(new_body, @new_name)
        end

        # Validate the patched body is valid before adding to patches
        unless new_body && new_body.include?("<<") && new_body.include?(">>")
          warn "Warning: Invalid patched body for #{fld.ref.inspect}, skipping update"
          return false
        end

        patches.reject! { |p| p[:ref] == fld.ref }
        patches << { ref: fld.ref, body: new_body }

        # If we renamed the field, also update the parent field object and all widgets
        if @new_name && !@new_name.empty?
          # Update parent field object if it exists (separate from widget)
          if field_ref != fld.ref
            field_body = resolver.object_body(field_ref)
            existing_field_patch = patches.find { |p| p[:ref] == field_ref }
            field_body = existing_field_patch[:body] if existing_field_patch
            
            if field_body && !field_body.include?("/Subtype /Widget")
              new_field_body = patch_field_name_body(field_body, @new_name)
              if new_field_body && new_field_body.include?("<<") && new_field_body.include?(">>")
                patches.reject! { |p| p[:ref] == field_ref }
                patches << { ref: field_ref, body: new_field_body }
              end
            end
          end
          
          # Update all widget annotations that reference this field
          update_widget_names_for_field(field_ref, @new_name)
        end

        # Also update any widget annotations that reference this field via /Parent
        update_widget_annotations_for_field(field_ref, @new_value)

        # Best-effort: set NeedAppearances to true so viewers regenerate appearances
        ensure_need_appearances

        true
      end

      private

      def resolver
        @document.instance_variable_get(:@resolver)
      end

      def patches
        @document.instance_variable_get(:@patches)
      end

      def patch_field_value_body(dict_body, new_value)
        # Simple, reliable approach: Use DictScan methods that preserve structure
        # Don't manipulate the dictionary body - let DictScan handle it

        # Ensure we have a valid dictionary
        return dict_body unless dict_body&.include?("<<")

        # Encode the new value
        v_token = DictScan.encode_pdf_string(new_value)

        # Find /V using pattern matching to ensure we get the complete key
        v_key_pattern = %r{/V(?=[\s(<\[/])}
        has_v = dict_body.match(v_key_pattern)

        # Update /V - use replace_key_value which handles the replacement carefully
        patched = if has_v
                    DictScan.replace_key_value(dict_body, "/V", v_token)
                  else
                    DictScan.upsert_key_value(dict_body, "/V", v_token)
                  end

        # Verify replacement worked and dictionary is still valid
        unless patched && patched.include?("<<") && patched.include?(">>")
          warn "Warning: Dictionary corrupted after /V replacement"
          return dict_body # Return original if corrupted
        end

        # Update /AS for checkboxes/radio buttons if needed
        # Check for /FT /Btn more carefully
        ft_pattern = %r{/FT\s+/Btn}
        if ft_pattern.match(patched) && (as_needed = DictScan.appearance_choice_for(new_value, patched))
          as_pattern = %r{/AS(?=[\s(<\[/])}
          has_as = patched.match(as_pattern)

          patched = if has_as
                      DictScan.replace_key_value(patched, "/AS", as_needed)
                    else
                      DictScan.upsert_key_value(patched, "/AS", as_needed)
                    end

          # Verify /AS replacement worked
          unless patched && patched.include?("<<") && patched.include?(">>")
            warn "Warning: Dictionary corrupted after /AS replacement"
            # Revert to before /AS change
            return DictScan.replace_key_value(dict_body, "/V", v_token) if has_v

            return dict_body
          end
        end

        patched
      end

      def patch_field_name_body(dict_body, new_name)
        # Ensure we have a valid dictionary
        return dict_body unless dict_body&.include?("<<")

        # Encode the new name
        t_token = DictScan.encode_pdf_string(new_name)

        # Find /T using pattern matching
        t_key_pattern = %r{/T(?=[\s(<\[/])}
        has_t = dict_body.match(t_key_pattern)

        # Update /T - use replace_key_value which handles the replacement carefully
        patched = if has_t
                    DictScan.replace_key_value(dict_body, "/T", t_token)
                  else
                    DictScan.upsert_key_value(dict_body, "/T", t_token)
                  end

        # Verify replacement worked and dictionary is still valid
        unless patched && patched.include?("<<") && patched.include?(">>")
          warn "Warning: Dictionary corrupted after /T replacement"
          return dict_body # Return original if corrupted
        end

        patched
      end

      def update_widget_annotations_for_field(field_ref, new_value)
        resolver.each_object do |ref, body|
          next unless body
          # Use flexible widget detection
          is_widget = body.include?("/Subtype") && body.include?("/Widget") && body =~ %r{/Subtype\s*/Widget}
          next unless is_widget
          next unless body.include?("/Parent")

          # Check for existing patch for this widget
          existing_patch = patches.find { |p| p[:ref] == ref }
          body = existing_patch[:body] if existing_patch

          parent_tok = DictScan.value_token_after("/Parent", body)
          next unless parent_tok && parent_tok =~ /\A(\d+)\s+(\d+)\s+R/

          widget_parent_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
          next unless widget_parent_ref == field_ref

          widget_body_patched = patch_field_value_body(body, new_value)
          # Remove any existing patch for this widget and add the new one
          patches.reject! { |p| p[:ref] == ref }
          patches << { ref: ref, body: widget_body_patched } if widget_body_patched != body
        end
      end

      def update_widget_names_for_field(field_ref, new_name)
        resolver.each_object do |ref, body|
          next unless body
          # Use flexible widget detection
          is_widget = body.include?("/Subtype") && body.include?("/Widget") && body =~ %r{/Subtype\s*/Widget}
          next unless is_widget

          # Check for existing patch for this widget
          existing_patch = patches.find { |p| p[:ref] == ref }
          body = existing_patch[:body] if existing_patch

          # Match widgets by /Parent reference
          if body.include?("/Parent")
            parent_tok = DictScan.value_token_after("/Parent", body)
            if parent_tok && parent_tok =~ /\A(\d+)\s+(\d+)\s+R/
              widget_parent_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
              if widget_parent_ref == field_ref
                widget_body_patched = patch_field_name_body(body, new_name)
                patches.reject! { |p| p[:ref] == ref }
                patches << { ref: ref, body: widget_body_patched } if widget_body_patched != body
              end
            end
          end

          # Also match widgets by field name (/T) - some widgets might not have /Parent
          if body.include?("/T")
            t_tok = DictScan.value_token_after("/T", body)
            if t_tok
              widget_name = DictScan.decode_pdf_string(t_tok)
              if widget_name && widget_name == @name
                widget_body_patched = patch_field_name_body(body, new_name)
                patches.reject! { |p| p[:ref] == ref }
                patches << { ref: ref, body: widget_body_patched } if widget_body_patched != body
              end
            end
          end
        end
      end

      def ensure_need_appearances
        af_ref = acroform_ref
        return unless af_ref

        acro_body = resolver.object_body(af_ref)
        existing_af_patch = patches.find { |p| p[:ref] == af_ref }
        acro_body = existing_af_patch[:body] if existing_af_patch

        return if acro_body.include?("/NeedAppearances")

        acro_patched = DictScan.upsert_key_value(acro_body, "/NeedAppearances", "true")
        # Remove any existing patch for AcroForm and add the new one
        patches.reject! { |p| p[:ref] == af_ref }
        patches << { ref: af_ref, body: acro_patched }
      end

      def acroform_ref
        @document.send(:acroform_ref)
      end
    end
  end
end
