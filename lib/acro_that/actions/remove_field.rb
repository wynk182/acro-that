# frozen_string_literal: true

module AcroThat
  module Actions
    # Action to remove a field from a PDF document
    class RemoveField
      def initialize(document, field)
        @document = document
        @field = field
      end

      def call
        af_ref = acroform_ref
        return false unless af_ref

        # Step 1: Remove widget annotations from pages' /Annots arrays
        remove_widget_annotations_from_pages

        # Step 2: Remove from /Fields array
        remove_from_fields_array(af_ref)

        # Step 3: Mark the field object as deleted by setting /T to empty
        mark_field_deleted

        true
      end

      private

      def resolver
        @document.instance_variable_get(:@resolver)
      end

      def patches
        @document.instance_variable_get(:@patches)
      end

      def remove_from_fields_array(af_ref)
        af_body = resolver.object_body(af_ref)
        existing_af_patch = patches.find { |p| p[:ref] == af_ref }
        af_body = existing_af_patch[:body] if existing_af_patch

        fields_array_ref = DictScan.value_token_after("/Fields", af_body)

        if fields_array_ref && fields_array_ref =~ /\A(\d+)\s+(\d+)\s+R/
          # Reference case: /Fields points to a separate array object
          arr_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
          arr_body = resolver.object_body(arr_ref)
          existing_arr_patch = patches.find { |p| p[:ref] == arr_ref }
          arr_body = existing_arr_patch[:body] if existing_arr_patch

          filtered = DictScan.remove_ref_from_array(arr_body, @field.ref)
          # Remove any existing patch for this array and add the new one
          patches.reject! { |p| p[:ref] == arr_ref }
          patches << { ref: arr_ref, body: filtered } if filtered != arr_body
        else
          # Inline array case: /Fields is inline in AcroForm dict
          filtered_af = DictScan.remove_ref_from_inline_array(af_body, "/Fields", @field.ref)
          if filtered_af
            # Remove any existing patch for AcroForm and add the new one
            patches.reject! { |p| p[:ref] == af_ref }
            patches << { ref: af_ref, body: filtered_af } if filtered_af != af_body
          end
        end
      end

      def mark_field_deleted
        fld_body = resolver.object_body(@field.ref)
        return unless fld_body

        # Check for existing patch for this field
        existing_patch = patches.find { |p| p[:ref] == @field.ref }
        fld_body = existing_patch[:body] if existing_patch

        # Set /T to empty string (list_fields requires /T with a name to identify fields)
        deleted_body = DictScan.replace_key_value(fld_body, "/T", "()")
        # Remove any existing patch for this field and add the new one
        patches.reject! { |p| p[:ref] == @field.ref }
        patches << { ref: @field.ref, body: deleted_body }
      end

      def remove_widget_annotations_from_pages
        widget_refs_to_remove = []

        # First, check if the field object itself is a widget (flat structure)
        field_body = resolver.object_body(@field.ref)
        existing_field_patch = patches.find { |p| p[:ref] == @field.ref }
        field_body = existing_field_patch[:body] if existing_field_patch

        if field_body
          is_widget = field_body.include?("/Subtype") && field_body.include?("/Widget") && field_body =~ %r{/Subtype\s*/Widget}
          if is_widget
            # The field object IS the widget - find its page and remove it
            widget_refs_to_remove << @field.ref
          end
        end

        # Second, find all widget annotations that reference this field via /Parent or /T (field name)
        resolver.each_object do |widget_ref, body|
          next unless body
          # Skip if we already added this one
          next if widget_ref == @field.ref

          # Use flexible widget detection (same as in update_field)
          is_widget = body.include?("/Subtype") && body.include?("/Widget") && body =~ %r{/Subtype\s*/Widget}
          next unless is_widget

          # Check for existing patch for this widget
          existing_patch = patches.find { |p| p[:ref] == widget_ref }
          body = existing_patch[:body] if existing_patch

          # Match by /Parent reference
          if body =~ %r{/Parent\s+(\d+)\s+(\d+)\s+R}
            widget_parent_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
            if widget_parent_ref == @field.ref
              widget_refs_to_remove << widget_ref
              next
            end
          end

          # Also match by field name (/T) - some widgets might not have /Parent
          next unless body.include?("/T") && @field.name

          t_tok = DictScan.value_token_after("/T", body)
          next unless t_tok

          widget_name = DictScan.decode_pdf_string(t_tok)
          if widget_name && widget_name == @field.name
            widget_refs_to_remove << widget_ref
          end
        end

        return if widget_refs_to_remove.empty?

        # For each widget, find its page and remove it from /Annots
        widget_refs_to_remove.each do |widget_ref|
          widget_body = resolver.object_body(widget_ref)
          existing_widget_patch = patches.find { |p| p[:ref] == widget_ref }
          widget_body = existing_widget_patch[:body] if existing_widget_patch

          # Find which page this widget is on via /P reference
          if widget_body && widget_body =~ %r{/P\s+(\d+)\s+(\d+)\s+R}
            page_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
            remove_widget_from_page_annots(page_ref, widget_ref)
          else
            # If no /P reference, search all pages for this widget
            # (some PDFs might not have /P on widgets)
            find_and_remove_widget_from_all_pages(widget_ref)
          end
        end
      end

      def find_and_remove_widget_from_all_pages(widget_ref)
        # Find all page objects and check their /Annots arrays
        page_objects = []
        resolver.each_object do |ref, body|
          next unless body

          is_page = body.include?("/Type /Page") ||
                    body.include?("/Type/Page") ||
                    (body.include?("/Type") && body.include?("/Page") && body =~ %r{/Type\s*/Page})
          next unless is_page

          page_objects << ref
        end

        # Check each page's /Annots array
        page_objects.each do |page_ref|
          remove_widget_from_page_annots(page_ref, widget_ref)
        end
      end

      def remove_widget_from_page_annots(page_ref, widget_ref)
        page_body = resolver.object_body(page_ref)
        return unless page_body

        existing_page_patch = patches.find { |p| p[:ref] == page_ref }
        page_body = existing_page_patch[:body] if existing_page_patch

        # Handle inline /Annots array
        if page_body =~ %r{/Annots\s*\[(.*?)\]}m
          annots_array_str = ::Regexp.last_match(1)
          # Remove the widget reference from the array
          filtered_array = annots_array_str.gsub(/\b#{widget_ref[0]}\s+#{widget_ref[1]}\s+R\b/, "").strip
          # Clean up extra spaces
          filtered_array.gsub!(/\s+/, " ")

          new_annots = if filtered_array.empty?
                         "[]"
                       else
                         "[#{filtered_array}]"
                       end

          new_page_body = page_body.sub(%r{/Annots\s*\[.*?\]}, "/Annots #{new_annots}")
          patches.reject! { |p| p[:ref] == page_ref }
          patches << { ref: page_ref, body: new_page_body } if new_page_body != page_body
        # Handle indirect /Annots array reference
        elsif page_body =~ %r{/Annots\s+(\d+)\s+(\d+)\s+R}
          annots_array_ref = [Integer(::Regexp.last_match(1)), Integer(::Regexp.last_match(2))]
          annots_array_body = resolver.object_body(annots_array_ref)

          if annots_array_body
            existing_annots_patch = patches.find { |p| p[:ref] == annots_array_ref }
            annots_array_body = existing_annots_patch[:body] if existing_annots_patch

            # Remove the widget reference from the array
            filtered_body = DictScan.remove_ref_from_array(annots_array_body, widget_ref)

            if filtered_body != annots_array_body
              patches.reject! { |p| p[:ref] == annots_array_ref }
              patches << { ref: annots_array_ref, body: filtered_body }
            end
          end
        end
      end

      def acroform_ref
        @document.send(:acroform_ref)
      end
    end
  end
end
