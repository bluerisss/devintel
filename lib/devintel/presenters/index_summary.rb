# frozen_string_literal: true

module DevIntel
  module Presenters
    # Renders an Index::Indexer::Result as plain text.
    #
    # The layout separates two kinds of number that are easy to confuse:
    #
    #   "This run"        what the indexer did just now
    #   "Index now holds" what the database contains afterwards
    #
    # A no-op run is the clearest case: it did nothing, yet the index still
    # holds every symbol from before. Mixing the two in one flat list made it
    # impossible to tell which was which, so each line carries its own label
    # and a short note saying what its number counts.
    class IndexSummary
      # Listing every unparsable file would bury the summary; the count stays
      # exact even when the list is cut short.
      MAX_LISTED_PATHS = 5

      # One "<count>  <label>  <note>" line.
      Row = Data.define(:count, :label, :note)

      def initialize(result)
        @result = result
      end

      def to_s
        "#{[heading, locations, run_section, index_section].join("\n\n")}\n"
      end

      private

      def heading
        "DevIntel Index"
      end

      def locations
        Table.rows([["Repository", @result.root.to_s], ["Database", relative_database_path]]).join("\n")
      end

      # What the indexer did. Every discovered file is in exactly one of
      # parsed / skipped; removals are files that have left the repository.
      def run_section
        section(
          format("This run took %.2fs", @result.duration),
          [discovered_row, parsed_row, skipped_row, removed_row]
        )
      end

      # What the index contains now, which is unrelated to how much work this
      # particular run had to do.
      def index_section
        rows = [symbols_row, relationships_row, traced_row, untraced_row,
                unattributed_row, unparsed_row]

        [section("Index now holds", rows), *listed_paths].join("\n")
      end

      def discovered_row
        counted_row(@result.discovered, "Ruby file", "found on disk")
      end

      def parsed_row
        Row.new(count: @result.parsed, label: "parsed",
                note: "#{@result.added} added, #{@result.modified} modified")
      end

      def skipped_row
        Row.new(count: @result.unchanged, label: "skipped", note: "unchanged since the last run")
      end

      def removed_row
        Row.new(count: @result.removed, label: "removed", note: "no longer on disk")
      end

      def symbols_row
        counted_row(@result.symbols, "symbol", breakdown(@result.symbol_types))
      end

      def relationships_row
        counted_row(@result.references, "relationship", breakdown(@result.reference_types))
      end

      def traced_row
        fixed_row(@result.traceable_references, "traced to code", breakdown(traceable_resolutions))
      end

      def untraced_row
        fixed_row(@result.untraceable_references, "left untraced", breakdown(untraceable_resolutions))
      end

      def traceable_resolutions
        @result.resolutions.select { |resolution, _| Graph::Resolution.traceable?(resolution) }
      end

      def untraceable_resolutions
        @result.resolutions.reject { |resolution, _| Graph::Resolution.traceable?(resolution) }
      end

      # Dropped rather than stored, so the count is the only place this shows up.
      def unattributed_row
        fixed_row(@result.unattributed_self_calls, "self-calls dropped",
                  "receiverless call not defined in its own scope")
      end

      def unparsed_row
        problem_row(@result.parse_errors, "unparsed file", "syntax error, so no symbols were stored")
      end

      # A row whose label is a countable noun, pluralised to match.
      def counted_row(count, noun, note)
        Row.new(count: count, label: pluralize(count, noun), note: note)
      end

      # A row whose label is a phrase, not a noun to be pluralised.
      def fixed_row(count, label, note)
        Row.new(count: count, label: label, note: note)
      end

      # A row whose note describes a situation that may not have arisen. At zero
      # the note is dropped: "0 unparsed files - syntax error" is a contradiction.
      def problem_row(count, noun, note)
        Row.new(count: count, label: pluralize(count, noun), note: count.zero? ? "" : note)
      end

      def section(title, rows)
        cells = rows.map { |row| [row.count, row.label, row.note] }

        [title, *Table.rows(cells, align: [Table::RIGHT])].join("\n")
      end

      # "class 4, method 3, constant 1"
      def breakdown(counts)
        counts.map { |type, total| "#{type.tr('_', ' ')} #{total}" }.join(", ")
      end

      def listed_paths
        paths = @result.parse_error_paths
        return [] if paths.empty?

        listed = paths.first(MAX_LISTED_PATHS).map { |path| "      #{path}" }
        remaining = paths.size - listed.size
        remaining.positive? ? listed + ["      ... and #{remaining} more"] : listed
      end

      def pluralize(count, noun)
        count == 1 ? noun : "#{noun}s"
      end

      def relative_database_path
        @result.database_path.relative_path_from(@result.root).to_s
      rescue ArgumentError
        @result.database_path.to_s
      end
    end
  end
end
