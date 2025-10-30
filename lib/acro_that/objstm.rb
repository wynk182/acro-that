# frozen_string_literal: true

module AcroThat
  class ObjStm
    # Parse an object stream body given N and First.
    # Returns: array like [{ ref:[obj_num,0], body:String }, ...] in order of header listing.
    def self.parse(bytes, n:, first:)
      head = bytes[0...first]
      entries = head.strip.split(/\s+/).map!(&:to_i)
      refs = []
      n.times do |i|
        obj = entries[2 * i]
        off = entries[(2 * i) + 1]
        next_off = i + 1 < n ? entries[(2 * (i + 1)) + 1] : (bytes.bytesize - first)
        body = bytes[first + off, (first + next_off) - (first + off)]
        refs << { ref: [obj, 0], body: body }
      end
      refs
    end
  end
end
