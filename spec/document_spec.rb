# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe AcroThat::Document do
  describe ".open" do
    it "parses a PDF from StringIO" do
      # Create a minimal PDF with AcroForm for testing
      pdf_content = create_test_pdf
      io = StringIO.new(pdf_content)

      doc = described_class.open(io)

      expect(doc).to be_a(described_class)
      expect(doc.objects).to be_a(Hash)
      expect(doc.xref).to be_a(AcroThat::Xref)
      expect(doc.xref.entries.keys).to include(1, 2, 3, 4)
    end

    it "finds the catalog" do
      pdf_content = create_test_pdf
      io = StringIO.new(pdf_content)

      doc = described_class.open(io)

      expect(doc.catalog).to be_a(Hash)
      expect(doc.catalog["/Type"]).to eq("/Catalog")
    end

    it "lists form fields" do
      pdf_content = create_test_pdf
      io = StringIO.new(pdf_content)

      doc = described_class.open(io)
      fields = doc.list_fields

      expect(fields).to be_an(Array)
      # Should find no fields since the test PDF has empty Fields array
      expect(fields).to be_empty
    end

    it "removes a field" do
      pdf_content = create_test_pdf
      io = StringIO.new(pdf_content)

      doc = described_class.open(io)
      initial_count = doc.list_fields.length

      # Try to remove a non-existent field
      doc.remove_field("TestField")
      remaining_fields = doc.list_fields

      # Should remain the same since field doesn't exist
      expect(remaining_fields.length).to eq(initial_count)
    end

    it "replaces a field" do
      pdf_content = create_test_pdf
      io = StringIO.new(pdf_content)

      doc = described_class.open(io)

      # Add a new field
      doc.replace_field("NewField", rect: [100, 500, 200, 520], value: "Test Value")
      fields = doc.list_fields

      # Should find the new field
      field_names = fields.map(&:fqn)
      expect(field_names).to include("NewField")
    end

    it "writes to StringIO" do
      pdf_content = create_test_pdf
      io = StringIO.new(pdf_content)

      doc = described_class.open(io)
      output = doc.write_to_string_io

      expect(output).to be_a(StringIO)
      expect(output.string).to start_with("%PDF-")
    end

    it "resolves objects inside object streams" do
      # Use the actual Stamford PDF that has compressed objects
      pdf_path = File.join(__dir__, "..", "..", "Stamford_Trade-Name-Dissolution.pdf")
      if File.exist?(pdf_path)
        io = StringIO.new(File.binread(pdf_path))
        doc = described_class.open(io)

        acro_ref = doc.catalog["/AcroForm"]
        expect(acro_ref).not_to be_nil

        acro = doc.deref(acro_ref)
        expect(acro).to be_a(Hash)
        expect(acro["/Fields"]).not_to be_nil
      else
        skip "Stamford PDF not found for compressed object test"
      end
    end
  end

  describe "Read sample pdf and list all fields" do
    it "lists all fields" do
      pdf_path = File.join(__dir__, "..", "..", "Stamford_Trade-Name-Dissolution.pdf")
      if File.exist?(pdf_path)
        io = StringIO.new(File.binread(pdf_path))
        doc = described_class.open(io)
        fields = doc.list_fields
        expect(fields).not_to be_nil
        expect(fields).not_to be_empty
        expect(fields.length).to be > 0
        expect(fields.first).to be_a(Hash)
        expect(fields.first["/T"]).not_to be_nil
        expect(fields.first["/T"]).not_to be_empty
      end
    end
  end

  private

  # Create a minimal test PDF with an AcroForm
  def create_test_pdf
    # This is a very basic PDF structure for testing
    # In a real implementation, you'd want a proper test PDF
    pdf_parts = []

    # Header
    pdf_parts << "%PDF-1.4"
    pdf_parts << "%\xE2\xE3\xCF\xD3"

    # Catalog object (1 0 obj)
    pdf_parts << "1 0 obj"
    pdf_parts << "<<"
    pdf_parts << "  /Type /Catalog"
    pdf_parts << "  /Pages 2 0 R"
    pdf_parts << "  /AcroForm 3 0 R"
    pdf_parts << ">>"
    pdf_parts << "endobj"

    # Pages object (2 0 obj)
    pdf_parts << "2 0 obj"
    pdf_parts << "<<"
    pdf_parts << "  /Type /Pages"
    pdf_parts << "  /Count 1"
    pdf_parts << "  /Kids [4 0 R]"
    pdf_parts << ">>"
    pdf_parts << "endobj"

    # AcroForm object (3 0 obj)
    pdf_parts << "3 0 obj"
    pdf_parts << "<<"
    pdf_parts << "  /Fields []"
    pdf_parts << "  /NeedAppearances false"
    pdf_parts << ">>"
    pdf_parts << "endobj"

    # Page object (4 0 obj)
    pdf_parts << "4 0 obj"
    pdf_parts << "<<"
    pdf_parts << "  /Type /Page"
    pdf_parts << "  /Parent 2 0 R"
    pdf_parts << "  /MediaBox [0 0 612 792]"
    pdf_parts << "  /Contents 6 0 R"
    pdf_parts << "  /Annots []"
    pdf_parts << ">>"
    pdf_parts << "endobj"

    # Xref table
    pdf_parts << "xref"
    pdf_parts << "0 5"
    pdf_parts << "0000000000 65535 f"  # Free object
    pdf_parts << "0000000010 00000 n"  # Object 1 (catalog)
    pdf_parts << "0000000050 00000 n"  # Object 2 (pages)
    pdf_parts << "0000000100 00000 n"  # Object 3 (acroform)
    pdf_parts << "0000000150 00000 n"  # Object 4 (page)

    # Trailer
    pdf_parts << "trailer"
    pdf_parts << "<<"
    pdf_parts << "  /Size 5"
    pdf_parts << "  /Root 1 0 R"
    pdf_parts << ">>"

    pdf_parts << "startxref"
    pdf_parts << "200"

    pdf_parts << "%%EOF"

    pdf_parts.join("\n")
  end
end
