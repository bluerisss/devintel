# frozen_string_literal: true

module DevIntel
  module Presenters
    # Renders an Index::Indexer::Result as plain text.
    #
    # Formatting lives here, not in the CLI command and not in the service, so
    # that output is testable without running Thor and so a future `--format
    # json` is an added presenter rather than a rewrite.
    class IndexSummary
      def initialize(result)
        @result = result
      end

      def to_s
        body = sections.map { |title, value| "#{title}:\n  #{value}" }.join("\n\n")
        "DevIntel Index\n\n#{body}\n"
      end

      private

      def sections
        [
          ["Repository", @result.root.to_s],
          ["Ruby files", @result.discovered.to_s],
          ["Changed", changed_line],
          ["Indexed", @result.indexed.to_s],
          ["Database", relative_database_path],
          ["Duration", format("%.2fs", @result.duration)]
        ]
      end

      def changed_line
        breakdown = "new #{@result.added}, modified #{@result.modified}, removed #{@result.removed}"
        "#{@result.changed}  (#{breakdown})"
      end

      def relative_database_path
        @result.database_path.relative_path_from(@result.root).to_s
      rescue ArgumentError
        @result.database_path.to_s
      end
    end
  end
end
