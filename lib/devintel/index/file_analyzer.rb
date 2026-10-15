# frozen_string_literal: true

module DevIntel
  module Index
    # Parses one file and replaces everything the index knows about it.
    #
    # Replace-per-file rather than diffing symbol by symbol: a file's symbols
    # are cheap to rebuild once it has been parsed, and a wholesale replace
    # cannot leave a stale symbol behind. Incremental work happens one level
    # up — unchanged files are never handed to this class at all.
    class FileAnalyzer
      OK    = "ok"
      ERROR = "error"

      Outcome = Data.define(:symbols, :references, :errors) do
        def failed?
          !errors.empty?
        end
      end

      def initialize(file_store, symbol_store, reference_store, parser: Parser::RubyParser)
        @file_store = file_store
        @symbol_store = symbol_store
        @reference_store = reference_store
        @parser = parser
      end

      # @return [Outcome]
      def call(file_id, source_file)
        @symbol_store.delete_for_file(file_id)
        @reference_store.delete_for_file(file_id)

        result = @parser.parse_file(source_file.absolute_path)
        @file_store.set_parse_state(file_id, result.failed? ? ERROR : OK)
        store(file_id, result) unless result.failed?

        Outcome.new(symbols: result.symbols.size, references: result.references.size, errors: result.errors)
      end

      private

      def store(file_id, result)
        symbol_ids = @symbol_store.insert_all(file_id, result.symbols)
        @reference_store.insert_all(file_id, result.references, symbol_ids)
      end
    end
  end
end
