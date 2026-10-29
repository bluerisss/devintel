# frozen_string_literal: true

module DevIntel
  module Presenters
    # Renders an Impact::Analyzer::Result as plain text.
    #
    # Each impacted symbol carries its confidence and the evidence for it, on
    # the same line, because a reader acting on this has to be able to tell a
    # call DevIntel read in the source from one it inferred.
    class Impact
      MAX_ROWS = 25

      def initialize(result)
        @result = result
      end

      def to_s
        "#{sections.compact.join("\n\n")}\n"
      end

      private

      def sections
        [heading, locations, changed, direct, indirect, entry_points, tests, untested, unmapped, footer]
      end

      def heading
        "DevIntel Impact"
      end

      def locations
        Table.rows([
                     ["Repository", @result.root.to_s],
                     ["Base", "#{@result.base}  (merge base #{@result.merge_base.to_s[0, 7]})"]
                   ]).join("\n")
      end

      def changed
        return "Changed symbols  none" if @result.changed.empty?

        rows = @result.changed.map { |symbol| [symbol.type, symbol.qualified_name, symbol.location] }

        section("Changed symbols", @result.changed.size, "what the diff landed on", rows)
      end

      def direct
        impact_section("Direct impact", @result.direct, "symbols that call a changed symbol")
      end

      def indirect
        impact_section("Indirect impact", @result.indirect,
                       "more than one step away, up to #{@result.depth_limit}")
      end

      def impact_section(title, impacted, note)
        return nil if impacted.empty?

        shown = impacted.sort_by { |row| [confidence_order(row.confidence), row.qualified_name] }
                        .first(MAX_ROWS)

        section(title, impacted.size, note, shown.map { |row| impact_row(row) },
                overflow: impacted.size - shown.size)
      end

      def impact_row(impacted)
        [impacted.confidence, impacted.qualified_name, impacted.evidence,
         "#{impacted.relation} #{impacted.via}"]
      end

      # Most certain first: that is the order a reader should act in.
      def confidence_order(confidence)
        levels = DevIntel::Impact::Confidence::LEVELS

        levels.index(confidence) || levels.size
      end

      # Either behaviour enters the system here, or nothing reaches the code.
      # Static analysis cannot tell those apart, so the heading says both.
      def entry_points
        return nil if @result.entry_points.empty?

        rows = @result.entry_points.first(MAX_ROWS).map { |name| [name] }

        section("Entry points", @result.entry_points.size,
                "nothing outside the tests calls these", rows,
                overflow: @result.entry_points.size - rows.size)
      end

      def tests
        return "Tests  none reference anything in this impact set" if @result.tests.empty?

        rows = @result.tests.first(MAX_ROWS).map do |path, names|
          [path, "covers #{names.first(3).join(', ')}"]
        end

        section("Tests", @result.tests.size, "files that reference an impacted symbol", rows,
                overflow: @result.tests.size - rows.size)
      end

      # Not proof that a symbol is untested, which is why the note says what
      # was actually checked.
      def untested
        return nil if @result.untested.empty?

        rows = @result.untested.map { |symbol| [symbol.qualified_name, symbol.location] }

        section("No test names these", @result.untested.size, "changed symbols no test file references", rows)
      end

      def unmapped
        return nil if @result.unmapped.empty?

        rows = @result.unmapped.map { |file| [file.path, file.state] }

        ["Changes with no symbols", *Table.rows(rows)].join("\n")
      end

      def footer
        return nil unless @result.truncated

        "Stopped at #{DevIntel::Impact::Analyzer::MAX_IMPACTED} impacted symbols; the change reaches further."
      end

      def section(title, count, note, rows, overflow: 0)
        lines = Table.rows(rows)
        lines << "  ... and #{overflow} more" if overflow.positive?

        ["#{title}  #{count}  -  #{note}", *lines].join("\n")
      end
    end
  end
end
