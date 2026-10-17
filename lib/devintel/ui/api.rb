# frozen_string_literal: true

require "json"

module DevIntel
  module UI
    # Builds the JSON payloads the UI reads.
    #
    # This class knows nothing about HTTP: it takes a question and returns a
    # Hash. That keeps the browser front-end replaceable — the API is the
    # contract, and swapping hand-written JavaScript for a framework later
    # should not touch anything below this line.
    #
    # It reuses Graph::SymbolGraph rather than querying the database itself:
    # one engine answers "what relates to what", and the UI is another caller
    # of it, not a second implementation.
    class Api
      DEFAULT_SEARCH_LIMIT = 50
      MAX_SEARCH_LIMIT = 200

      Failure = Data.define(:status, :body)

      def initialize(workspace)
        @workspace = workspace
      end

      def stats
        with_graph do |_graph, connection|
          {
            repository: @workspace.root.to_s,
            files: Database::FileStore.new(connection).count,
            symbols: Database::SymbolStore.new(connection).count,
            relationships: Database::ReferenceStore.new(connection).count
          }
        end
      end

      def search(query, limit: DEFAULT_SEARCH_LIMIT)
        return { query: query.to_s, results: [] } if query.to_s.strip.empty?

        with_graph do |graph, _connection|
          results = graph.search(query.to_s.strip, limit: clamp(limit))
          { query: query.to_s.strip, results: results.map { |result| definition_json(result) } }
        end
      end

      # @return [Hash, Failure]
      def symbol(name)
        trace = Graph::Trace.call(@workspace, name.to_s)
        trace_json(trace)
      rescue SymbolNotFoundError => e
        Failure.new(status: 404, body: { error: e.message, code: "symbol_not_found" })
      rescue AmbiguousSymbolError => e
        Failure.new(status: 409, body: { error: e.message, code: "ambiguous_symbol" })
      end

      private

      def with_graph
        unless @workspace.database_path.exist?
          raise IndexNotFoundError,
                "No index at #{@workspace.database_path}."
        end

        Database::Connection.open(@workspace.database_path) do |connection|
          yield(Graph::SymbolGraph.new(connection), connection)
        end
      end

      def clamp(limit)
        limit.to_i.clamp(1, MAX_SEARCH_LIMIT)
      end

      def trace_json(trace)
        {
          query: trace.query,
          definitions: trace.definitions.map { |definition| definition_json(definition) },
          callers: trace.callers.map { |relation| relation_json(relation) },
          callees: trace.callees.map { |relation| relation_json(relation) },
          untraced: trace.untraced,
          tests: trace.tests.map { |test| { path: test.path, line: test.line, type: test.type } }
        }
      end

      def definition_json(definition)
        {
          qualified_name: definition.qualified_name, type: definition.type,
          path: definition.path, line_start: definition.line_start, line_end: definition.line_end
        }
      end

      # `evidence` travels with every relationship so the UI cannot render an
      # inference as though it were an observation.
      def relation_json(relation)
        {
          qualified_name: relation.qualified_name, type: relation.type,
          resolution: relation.resolution, evidence: relation.evidence_class,
          reaches: relation.reaches, location: relation.location, occurrences: relation.occurrences
        }
      end
    end
  end
end
