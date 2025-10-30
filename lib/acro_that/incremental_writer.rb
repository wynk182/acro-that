# frozen_string_literal: true

module AcroThat
  # Appends an incremental update containing the given patches.
  # Each patch is {ref:[num,gen], body:String}
  class IncrementalWriter
    def initialize(original_bytes, patches)
      @orig = original_bytes
      @patches = patches
    end

    def render
      return @orig if @patches.empty?

      startxref_prev = find_startxref(@orig) or raise "startxref not found"
      max_obj = scan_max_obj_number(@orig)

      # Ensure we end with a newline before appending
      original_with_newline = @orig.dup
      original_with_newline << "\n" unless @orig.end_with?("\n")

      buf = +""
      offsets = []
      @patches.each do |p|
        num, gen = p[:ref]
        offset = original_with_newline.bytesize + buf.bytesize
        offsets << [num, gen, offset]

        # Write object with proper formatting
        buf << "#{num} #{gen} obj\n"
        buf << p[:body]
        buf << "\nendobj\n"
      end

      # Build xref table
      sorted = offsets.sort_by { |n, g, _| [n, g] }
      xref = +"xref\n"

      i = 0
      while i < sorted.length
        first_num = sorted[i][0]
        run = 1
        while (i + run) < sorted.length && sorted[i + run][0] == first_num + run && sorted[i + run][1] == sorted[i][1]
          run += 1
        end
        xref << "#{first_num} #{run}\n"
        run.times do |r|
          abs = sorted[i + r][2]
          gen = sorted[i + r][1]
          xref << format("%010d %05d n \n", abs, gen)
        end
        i += run
      end

      # Debug: verify xref was built
      if xref == "xref\n"
        raise "Xref table is empty! Offsets: #{offsets.inspect}"
      end

      # Build trailer with /Root reference
      new_size = [max_obj + 1, @patches.map { |p| p[:ref][0] }.max.to_i + 1].max
      xref_offset = original_with_newline.bytesize + buf.bytesize

      # Extract /Root from original trailer
      root_ref = extract_root_from_trailer(@orig)
      root_entry = root_ref ? " /Root #{root_ref}" : ""

      trailer = "trailer\n<< /Size #{new_size} /Prev #{startxref_prev}#{root_entry} >>\nstartxref\n#{xref_offset}\n%%EOF\n"

      result = original_with_newline + buf + xref + trailer

      # Verify xref was built correctly
      if xref.length < 10
        warn "Warning: xref table seems too short (#{xref.length} bytes). Expected proper entries."
      end

      result
    end

    private

    def find_startxref(bytes)
      if bytes =~ /startxref\s+(\d+)\s*%%EOF\s*\z/m
        return Integer(::Regexp.last_match(1))
      end

      m = bytes.rindex("startxref")
      return nil unless m

      tail = bytes[m, bytes.length - m]
      tail[/startxref\s+(\d+)/m, 1]&.to_i
    end

    def scan_max_obj_number(bytes)
      max = 0
      bytes.scan(/(^|\s)(\d+)\s+(\d+)\s+obj\b/) { max = [::Regexp.last_match(2).to_i, max].max }
      max
    end

    def extract_root_from_trailer(bytes)
      # For xref streams, find the last xref stream object dictionary
      startxref_match = bytes.match(/startxref\s+(\d+)\s*%%EOF\s*\z/m)
      if startxref_match
        xref_offset = startxref_match[1].to_i

        # Check if it's an xref stream (starts with object header)
        if bytes[xref_offset, 50] =~ /(\d+\s+\d+\s+obj)/
          # Find the dictionary in the xref stream object
          dict_start = bytes.index("<<", xref_offset)
          if dict_start
            trailer_section = bytes[dict_start, 500]
            if trailer_section =~ %r{/Root\s+(\d+\s+\d+\s+R)}
              return ::Regexp.last_match(1)
            end
          end
        end
      end

      # Fallback: look for classic trailer
      trailer_idx = bytes.rindex("trailer")
      if trailer_idx
        dict_start = bytes.index("<<", trailer_idx)
        if dict_start
          trailer_section = bytes[dict_start, 500]
          if trailer_section =~ %r{/Root\s+(\d+\s+\d+\s+R)}
            return ::Regexp.last_match(1)
          end
        end
      end

      nil
    end
  end
end
