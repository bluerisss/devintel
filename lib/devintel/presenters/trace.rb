# frozen_string_literal: true

module DevIntel
  module Presenters
    # Renders a Graph::Trace::Result as plain text.
    #
    # Every relationship line carries its evidence class, because a caller
    # DevIntel is certain about and one it inferred from `Foo.new` must not
    # look the same.
    class Trace
      # Long lists stop being readable; the count stays exact.
      MAX_ROWS = 25

      def initialize(result)
        @result = result
      end

      def to_s
        "#{sections.compact.join("\n\n")}\n"
      end

      private

      def sections
        [heading, definitions, relations("Callers", @result.callers, "reach this symbol"),
         callees_section, tests]
      end

      def heading
        @result.query
      end

      def definitions
        return "  not defined in this repository" if @result.definitions.empty?

        width = @result.definitions.map { |definition| definition.type.length }.max
        @result.definitions.map do |definition|
          format("  %-#{width}s  %s:%d-%d", definition.type, definition.path,
                 definition.line_start, definition.line_end)
        end.join("\n")
      end

      def callees_section
        body = relations("Callees", @result.callees, "this symbol reaches")
        return body if @result.untraced.empty?

        "#{body || "Callees  this symbol reaches\n  none"}\n#{untraced_note}"
      end

      # Relationships that exist but lead somewhere DevIntel cannot follow are
      # summarised rather than hidden: an empty Callees list would otherwise
      # read as "this symbol depends on nothing".
      def untraced_note
        total = @result.untraced.values.sum
        detail = @result.untraced.map { |resolution, count| "#{resolution.tr('_', ' ')} #{count}" }.join(", ")

        "  + #{total} #{pluralize(total, 'relationship')} DevIntel could not follow  (#{detail})"
      end

      def relations(title, relations, note)
        return nil if relations.empty?

        shown = relations.first(MAX_ROWS)
        rows = render_rows(shown)
        remaining = relations.size - shown.size
        rows << "  ... and #{remaining} more" if remaining.positive?

        ["#{title}  #{note}", *rows].join("\n")
      end

      def render_rows(relations)
        cells = relations.map { |relation| cells_for(relation) }

        Table.rows(cells).zip(relations).map { |line, relation| "#{line}  #{suffix(relation)}".rstrip }
      end

      def cells_for(relation)
        [relation.qualified_name, relation.type, relation.evidence_class, reaches(relation)]
      end

      def suffix(relation)
        "#{relation.location}#{occurrences(relation)}"
      end

      # Which member of the traced symbol this edge lands on, shown relative to
      # the symbol itself: "#parse_error_paths" rather than the full name, and
      # blank when the edge lands on the symbol as a whole.
      def reaches(relation)
        return "" if relation.reaches.nil?

        relation.reaches.delete_prefix(@result.query)
      end

      def occurrences(relation)
        relation.occurrences > 1 ? "  (#{relation.occurrences} sites)" : ""
      end

      def tests
        return nil if @result.tests.empty?

        rows = @result.tests.first(MAX_ROWS).map { |test| "  #{test.path}" }
        remaining = @result.tests.size - rows.size
        rows << "  ... and #{remaining} more" if remaining.positive?

        ["Tests  files that name this symbol", *rows].join("\n")
      end

      def pluralize(count, noun)
        count == 1 ? noun : "#{noun}s"
      end
    end
  end
end
