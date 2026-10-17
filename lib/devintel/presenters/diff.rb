# frozen_string_literal: true

module DevIntel
  module Presenters
    # Renders a Diff::Analyzer::Result as plain text.
    #
    # Three sections, in the order a reader needs them: what changed, which
    # symbols those changes land on, and - just as importantly - which changed
    # files produced no symbols and why. Leaving the third out would make a
    # partial answer look complete.
    class Diff
      MAX_LINE_RANGES = 6
      REINDEX = "  ->  run `devintel index`"

      def initialize(result)
        @result = result
      end

      def to_s
        "#{sections.compact.join("\n\n")}\n"
      end

      private

      def sections
        [heading, locations, changed_files, changed_symbols, unmapped]
      end

      def heading
        "DevIntel Diff"
      end

      def locations
        Table.rows([
                     ["Repository", @result.root.to_s],
                     ["Base", "#{@result.base}  (merge base #{short(@result.merge_base)})"]
                   ]).join("\n")
      end

      def changed_files
        return "Changed files\n  none" if @result.files.empty?

        rows = @result.files.map { |file| [file.status, file.path, lines_of(file)] }

        section("Changed files", @result.files.size, rows)
      end

      def changed_symbols
        symbols = @result.symbols
        return "Changed symbols  none" if symbols.empty?

        rows = symbols.map { |symbol| [symbol.type, symbol.qualified_name, symbol.location] }

        section("Changed symbols", symbols.size, rows)
      end

      # Every changed file that yielded nothing, with the reason. A reader has
      # to be able to tell "nothing depends on this" from "DevIntel could not
      # look".
      def unmapped
        files = @result.unmapped
        return nil if files.empty?

        rows = files.map { |file| [file.path, "#{file.state}#{remedy(file)}"] }

        ["No symbols mapped", *Table.rows(rows)].join("\n")
      end

      def section(title, count, rows)
        ["#{title}  #{count}", *Table.rows(rows)].join("\n")
      end

      def remedy(file)
        file.state == DevIntel::Diff::Analyzer::STALE ? REINDEX : ""
      end

      def lines_of(file)
        return "" if file.lines.empty?

        shown = file.lines.first(MAX_LINE_RANGES).map { |range| format_range(range) }
        remaining = file.lines.size - shown.size
        shown << "+#{remaining} more" if remaining.positive?

        "#{label_for(file)} #{shown.join(', ')}"
      end

      # Singular only when the change really is one line, not one range of many.
      def label_for(file)
        file.lines.one? && file.lines.first.size == 1 ? "line" : "lines"
      end

      def format_range(range)
        range.first == range.last ? range.first.to_s : "#{range.first}-#{range.last}"
      end

      def short(sha)
        sha.to_s[0, 7]
      end
    end
  end
end
