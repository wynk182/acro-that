# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "Encoding and Transliteration" do
  describe "DictScan.transliterate_to_ascii" do
    it "transliterates accented characters to ASCII" do
      expect(AcroThat::DictScan.transliterate_to_ascii("María")).to eq("Maria")
      expect(AcroThat::DictScan.transliterate_to_ascii("José")).to eq("Jose")
      expect(AcroThat::DictScan.transliterate_to_ascii("François")).to eq("Francois")
      expect(AcroThat::DictScan.transliterate_to_ascii("Café")).to eq("Cafe")
    end

    it "handles strings with multiple special characters" do
      expect(AcroThat::DictScan.transliterate_to_ascii("María Valentina")).to eq("Maria Valentina")
      expect(AcroThat::DictScan.transliterate_to_ascii("José María")).to eq("Jose Maria")
      expect(AcroThat::DictScan.transliterate_to_ascii("François Müller")).to eq("Francois Muller")
    end

    it "handles strings with no special characters" do
      expect(AcroThat::DictScan.transliterate_to_ascii("John Smith")).to eq("John Smith")
      expect(AcroThat::DictScan.transliterate_to_ascii("Test123")).to eq("Test123")
    end

    it "handles empty strings" do
      expect(AcroThat::DictScan.transliterate_to_ascii("")).to eq("")
    end

    it "handles non-string inputs" do
      expect(AcroThat::DictScan.transliterate_to_ascii(nil)).to be_nil
      expect(AcroThat::DictScan.transliterate_to_ascii(123)).to eq(123)
    end

    it "handles various accented characters from different languages" do
      expect(AcroThat::DictScan.transliterate_to_ascii("áéíóú")).to eq("aeiou")
      expect(AcroThat::DictScan.transliterate_to_ascii("ñ")).to eq("n")
      expect(AcroThat::DictScan.transliterate_to_ascii("ü")).to eq("u")
      expect(AcroThat::DictScan.transliterate_to_ascii("ç")).to eq("c")
    end
  end

  describe "DictScan.encode_pdf_string" do
    it "encodes strings with special characters without raising encoding errors" do
      expect do
        result = AcroThat::DictScan.encode_pdf_string("María Valentina")
        expect(result).to be_a(String)
        expect(result).to start_with("(")
        expect(result).to end_with(")")
      end.not_to raise_error
    end

    it "transliterates special characters before encoding" do
      result = AcroThat::DictScan.encode_pdf_string("María")
      # Should encode as "(Maria)" since it's transliterated to ASCII
      expect(result).to eq("(Maria)")
    end

    it "handles ASCII-only strings normally" do
      expect(AcroThat::DictScan.encode_pdf_string("John Smith")).to eq("(John Smith)")
      expect(AcroThat::DictScan.encode_pdf_string("Test123")).to eq("(Test123)")
    end

    it "escapes special PDF characters in ASCII strings" do
      result = AcroThat::DictScan.encode_pdf_string("Test (value)")
      expect(result).to include("\\(")
      expect(result).to include("\\)")
    end

    it "handles boolean values" do
      expect(AcroThat::DictScan.encode_pdf_string(true)).to eq("true")
      expect(AcroThat::DictScan.encode_pdf_string(false)).to eq("false")
    end

    it "handles symbol values" do
      expect(AcroThat::DictScan.encode_pdf_string(:test)).to eq("/test")
    end

    it "does not raise Encoding::CompatibilityError with various special characters" do
      special_chars = [
        "María Valentina",
        "José María",
        "François Müller",
        "Café",
        "São Paulo",
        "München",
        "Zürich"
      ]

      special_chars.each do |str|
        expect do
          AcroThat::DictScan.encode_pdf_string(str)
        end.not_to raise_error
      end
    end
  end

  describe "DictScan.encode_pdf_name" do
    it "encodes PDF names with special characters without raising encoding errors" do
      expect do
        result = AcroThat::DictScan.encode_pdf_name("María")
        expect(result).to be_a(String)
        expect(result).to start_with("/")
      end.not_to raise_error
    end

    it "transliterates special characters before encoding" do
      result = AcroThat::DictScan.encode_pdf_name("María")
      # Should transliterate to "Maria" and encode as PDF name
      expect(result).to eq("/Maria")
    end

    it "handles names with special PDF characters" do
      result = AcroThat::DictScan.encode_pdf_name("Test (value)")
      # Parentheses should be hex-encoded
      expect(result).to include("#28") # ( in hex
      expect(result).to include("#29") # ) in hex
    end

    it "does not raise Encoding::CompatibilityError with special characters" do
      special_chars = %w[
        María
        José
        François
        Café
      ]

      special_chars.each do |str|
        expect do
          AcroThat::DictScan.encode_pdf_name(str)
        end.not_to raise_error
      end
    end
  end

  describe "Integration with PDF operations" do
    let(:example_pdf) { File.join(__dir__, "fixtures", "form.pdf") }

    it "can update text fields with special characters" do
      doc = AcroThat::Document.new(example_pdf)
      fields = doc.list_fields
      expect(fields).not_to be_empty

      original_field = fields.first
      special_chars_value = "María Valentina"

      expect do
        result = doc.update_field(original_field.name, special_chars_value)
        expect(result).to be true
      end.not_to raise_error

      # Write and verify
      temp_file = Tempfile.new(["test_encoding", ".pdf"])
      begin
        doc.write(temp_file.path)

        # Reload and verify transliteration
        doc2 = AcroThat::Document.new(temp_file.path)
        fields2 = doc2.list_fields
        updated_field = fields2.find { |f| f.name == original_field.name }
        expect(updated_field).not_to be_nil
        expect(updated_field.value).to eq("Maria Valentina")
      ensure
        temp_file.unlink
      end
    end

    it "can add text fields with special character values" do
      doc = AcroThat::Document.new(example_pdf)

      expect do
        result = doc.add_field("TestField",
                               value: "María Valentina",
                               x: 100,
                               y: 500,
                               width: 200,
                               height: 20,
                               page: 1)
        expect(result).to be_a(AcroThat::Field)
      end.not_to raise_error

      # Write and verify
      temp_file = Tempfile.new(["test_add_encoding", ".pdf"])
      begin
        doc.write(temp_file.path)

        # Reload and verify
        doc2 = AcroThat::Document.new(temp_file.path)
        fields = doc2.list_fields
        test_field = fields.find { |f| f.name == "TestField" }
        expect(test_field).not_to be_nil
        expect(test_field.value).to eq("Maria Valentina")
      ensure
        temp_file.unlink
      end
    end

    it "can create radio buttons with special character export values" do
      doc = AcroThat::Document.new(example_pdf)

      expect do
        result1 = doc.add_field("Radio1",
                                type: :radio,
                                group_id: "encoding_test",
                                value: "María",
                                x: 100,
                                y: 500,
                                width: 20,
                                height: 20,
                                page: 1,
                                selected: true)
        expect(result1).to be_a(AcroThat::Field)

        result2 = doc.add_field("Radio2",
                                type: :radio,
                                group_id: "encoding_test",
                                value: "José",
                                x: 100,
                                y: 470,
                                width: 20,
                                height: 20,
                                page: 1)
        expect(result2).to be_a(AcroThat::Field)
      end.not_to raise_error

      # Write and verify
      temp_file = Tempfile.new(["test_radio_encoding", ".pdf"])
      begin
        doc.write(temp_file.path)

        # Verify the PDF was created successfully
        expect(File.exist?(temp_file.path)).to be true
        expect(File.size(temp_file.path)).to be > 0
      ensure
        temp_file.unlink
      end
    end

    it "can handle multiple operations with special characters" do
      doc = AcroThat::Document.new(example_pdf)
      fields = doc.list_fields
      expect(fields).not_to be_empty

      # Update existing field
      expect do
        doc.update_field(fields.first.name, "María")
      end.not_to raise_error

      # Add new field
      expect do
        doc.add_field("NewField", value: "José", x: 100, y: 500, width: 200, height: 20, page: 1)
      end.not_to raise_error

      # Write and verify
      temp_file = Tempfile.new(["test_multiple_encoding", ".pdf"])
      begin
        expect do
          doc.write(temp_file.path)
        end.not_to raise_error

        # Verify PDF is valid
        doc2 = AcroThat::Document.new(temp_file.path)
        fields2 = doc2.list_fields
        expect(fields2.length).to be > 0
      ensure
        temp_file.unlink
      end
    end

    it "handles field names with special characters" do
      doc = AcroThat::Document.new(example_pdf)

      expect do
        result = doc.add_field("María",
                               value: "Test Value",
                               x: 100,
                               y: 500,
                               width: 200,
                               height: 20,
                               page: 1)
        expect(result).to be_a(AcroThat::Field)
      end.not_to raise_error

      # Write and verify
      temp_file = Tempfile.new(["test_field_name_encoding", ".pdf"])
      begin
        doc.write(temp_file.path)

        # Reload and verify field name was transliterated
        doc2 = AcroThat::Document.new(temp_file.path)
        fields = doc2.list_fields
        test_field = fields.find { |f| f.name == "Maria" }
        expect(test_field).not_to be_nil
      ensure
        temp_file.unlink
      end
    end
  end

  describe "Edge cases" do
    it "handles strings with mixed ASCII and special characters" do
      result = AcroThat::DictScan.encode_pdf_string("John María Smith")
      expect(result).to eq("(John Maria Smith)")
    end

    it "handles strings with only special characters" do
      result = AcroThat::DictScan.encode_pdf_string("áéíóú")
      expect(result).to eq("(aeiou)")
    end

    it "handles very long strings with special characters" do
      long_string = "María " * 100
      expect do
        result = AcroThat::DictScan.encode_pdf_string(long_string)
        expect(result).to be_a(String)
      end.not_to raise_error
    end

    it "handles strings with newlines and special characters" do
      result = AcroThat::DictScan.encode_pdf_string("María\nValentina")
      expect(result).to include("\\n")
      expect(result).to include("Maria")
    end
  end
end
