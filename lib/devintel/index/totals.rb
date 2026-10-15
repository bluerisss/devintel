# frozen_string_literal: true

module DevIntel
  module Index
    # Reads what the index holds once a run has finished.
    #
    # Separate from the Indexer because it answers a different question: the
    # Indexer knows what this run did, these are facts about the database as it
    # now stands, and a run that did nothing still has to report them.
    module Totals
      def self.call(connection)
        symbols = Database::SymbolStore.new(connection)
        references = Database::ReferenceStore.new(connection)

        {
          symbols: symbols.count,
          symbol_types: symbols.count_by_type,
          references: references.count,
          reference_types: references.count_by_type,
          resolutions: references.count_by_resolution,
          parse_error_paths: Database::FileStore.new(connection).parse_error_paths
        }
      end
    end
  end
end
