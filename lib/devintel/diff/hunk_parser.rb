# frozen_string_literal: true

module DevIntel
  module Diff
    # Reads changed line numbers out of a unified diff.
    #
    # Only the *new* side is kept, because that is what the index describes:
    # mapping a change to a symbol means asking which symbol occupies those
    # lines in the file as it stands now.
    module HunkParser
      FILE_HEADER = %r{\A\+\+\+ (?:b/)?(.*)\z}
      HUNK = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/
      # Git writes this exact literal on every platform, so File::NULL - which
      # is "NUL" on Windows - would be wrong here.
      NO_FILE = "/dev/null" # rubocop:disable Style/FileNull

      # @return [Hash{String => Array<Range>}] changed line ranges per path.
      def self.call(patch)
        files = Hash.new { |hash, key| hash[key] = [] }
        path = nil

        patch.each_line do |line|
          if (header = FILE_HEADER.match(line.chomp))
            path = normalize(header[1])
          elsif path && (hunk = HUNK.match(line))
            files[path] << range_for(hunk)
          end
        end

        files
      end

      # A hunk with a count of 0 removed lines without adding any. The change
      # is real and it belongs to whatever symbol surrounds that point, so the
      # line next to the removal is recorded rather than nothing at all.
      def self.range_for(hunk)
        start = [hunk[1].to_i, 1].max
        count = hunk[2] ? hunk[2].to_i : 1

        count.zero? ? (start..start) : (start..(start + count - 1))
      end
      private_class_method :range_for

      # Git quotes a path when it contains unusual characters; `core.quotepath`
      # is already off, so only genuinely odd names arrive quoted.
      def self.normalize(path)
        return nil if path == NO_FILE
        return path unless path.start_with?('"') && path.end_with?('"')

        path[1..-2].gsub(/\\(.)/) { Regexp.last_match(1) }
      end
      private_class_method :normalize
    end
  end
end
