# frozen_string_literal: true

module CorpPdf
  # Represents a PDF form field
  class Field
    attr_accessor :value
    attr_reader :name, :type, :ref, :x, :y, :width, :height, :page

    TYPES = {
      text: "/Tx",
      button: "/Btn",
      checkbox: "/Btn",
      radio: "/Btn",
      choice: "/Ch",
      signature: "/Sig"
    }.freeze

    # Reverse lookup: map type strings to symbol keys
    TYPE_KEYS = TYPES.invert.freeze

    def initialize(name, value, type, ref, document = nil, position = {})
      @name = name
      @value = value
      # Normalize type: accept symbol keys or type strings, default to "/Tx"
      normalized_type = if type.is_a?(Symbol)
                          TYPES[type] || "/Tx"
                        else
                          type.to_s.strip
                        end
      @type = normalized_type.empty? ? "/Tx" : normalized_type
      @ref = ref
      @document = document
      @x = position[:x]
      @y = position[:y]
      @width = position[:width]
      @height = position[:height]
      @page = position[:page]
    end

    # Check if this is a text field
    def text_field?
      type == "/Tx"
    end

    # Check if this is a button field (checkbox/radio)
    def button_field?
      type == "/Btn"
    end

    # Check if this is a choice field (dropdown/list)
    def choice_field?
      type == "/Ch"
    end

    # Check if this is a signature field
    def signature_field?
      type == "/Sig"
    end

    # Check if the field has a value
    def has_value?
      !value.nil? && !value.to_s.empty?
    end

    # Get the object number (first element of ref)
    def object_number
      ref[0]
    end

    # Get the generation number (second element of ref)
    def generation
      ref[1]
    end

    # Check if field reference is valid (not [-1, 0] placeholder)
    def valid_ref?
      ref != [-1, 0]
    end

    # Equality comparison
    def ==(other)
      return false unless other.is_a?(Field)

      name == other.name &&
        value == other.value &&
        type == other.type &&
        ref == other.ref
    end

    # String representation for debugging
    def to_s
      type_str = type.inspect
      type_str += " (:#{type_key})" if type_key
      pos_str = if x && y && width && height
                  " x=#{x} y=#{y} w=#{width} h=#{height}"
                else
                  " position=(unknown)"
                end
      page_str = page ? " page=#{page}" : ""
      "#<CorpPdf::Field name=#{name.inspect} type=#{type_str} value=#{value.inspect} ref=#{ref.inspect}#{pos_str}#{page_str}>"
    end

    alias inspect to_s

    # Check if position is known
    def has_position?
      !x.nil? && !y.nil? && !width.nil? && !height.nil?
    end

    # Get the symbol key for the field type (e.g., :text for "/Tx")
    # Returns nil if the type is not in the TYPES mapping
    def type_key
      TYPE_KEYS[type]
    end

    # Update this field's value and optionally rename it in the document
    # Returns true if the field was found and queued for write.
    def update(new_value, new_name: nil)
      return false unless @document
      return false unless valid_ref?

      action = Actions::UpdateField.new(@document, @name, new_value, new_name: new_name)
      result = action.call

      # Update the local value if update was successful
      @value = new_value if result
      # Update the local name if rename was successful
      @name = new_name if result && new_name && !new_name.empty?

      result
    end

    # Remove this field from the AcroForm /Fields array and mark the field object as deleted.
    # Note: This does not purge page /Annots widgets (non-trivial); most viewers will hide the field
    # once it is no longer in the field tree.
    # Returns true if the field was removed.
    def remove
      return false unless @document
      return false unless valid_ref?

      action = Actions::RemoveField.new(@document, self)
      action.call
    end
  end
end
