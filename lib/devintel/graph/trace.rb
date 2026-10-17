# frozen_string_literal: true

module DevIntel
  module Graph
    # Application service behind `devintel trace`.
    #
    # Collects, for one symbol: where it is defined, what reaches it, what it
    # reaches, and which test files name it — each with the file and line that
    # is the evidence for it.
    class Trace
      # Several call sites from the same definition are one relationship to a
      # reader; `occurrences` keeps the rest from being lost.
      Relation = Data.define(:qualified_name, :type, :resolution, :reaches, :location, :occurrences) do
        def evidence_class
          Resolution.evidence_class(resolution)
        end
      end

      # A file that exercises the symbol, plus how we know.
      TestFile = Data.define(:path, :line, :type)

      # Which files count as tests. This is policy, not a fact about the graph,
      # so it lives with the service rather than with the queries: a spec earns
      # the link by *referencing* the symbol, and this only decides which of
      # those referencing files are tests.
      TEST_PATH = %r{(\A|/)(spec|test)/|_spec\.rb\z|_test\.rb\z}

      Result = Data.define(:query, :definitions, :callers, :callees, :untraced, :tests)

      def self.call(workspace, query)
        new(workspace, query).call
      end

      def initialize(workspace, query)
        @workspace = workspace
        @query = query
      end

      def call
        raise IndexNotFoundError, index_missing_message unless @workspace.database_path.exist?

        Database::Connection.open(@workspace.database_path) do |connection|
          build(SymbolGraph.new(connection))
        end
      end

      private

      def build(graph)
        name = resolve_name(graph)
        callers = graph.callers(name)
        callees = graph.callees(name)

        Result.new(
          query: name,
          definitions: graph.definitions(name),
          callers: group(callers),
          callees: group(traceable(callees)),
          untraced: summarise(callees),
          tests: tests(callers)
        )
      end

      def traceable(edges)
        edges.select { |edge| Resolution.traceable?(edge.resolution) }
      end

      # Edges that lead where DevIntel cannot follow are counted rather than
      # listed: they are real relationships, and an empty callee list would
      # otherwise read as "this symbol depends on nothing".
      def summarise(edges)
        edges.reject { |edge| Resolution.traceable?(edge.resolution) }
             .group_by(&:resolution)
             .transform_values(&:size)
      end

      def tests(callers)
        callers.select { |edge| TEST_PATH.match?(edge.path) }
               .group_by(&:path)
               .map { |path, edges| TestFile.new(path: path, line: edges.first.line, type: edges.first.type) }
      end

      # An exact qualified name wins; otherwise a unique simple name is
      # accepted, and an ambiguous one is reported rather than picked for them.
      def resolve_name(graph)
        return @query unless graph.definitions(@query).empty?

        candidates = graph.find_by_name(@query).map(&:qualified_name).uniq
        raise SymbolNotFoundError, "No symbol named #{@query} in the index." if candidates.empty?
        return candidates.first if candidates.one?

        raise AmbiguousSymbolError,
              "#{@query} matches #{candidates.size} symbols:\n" \
              "#{candidates.map { |candidate| "  #{candidate}" }.join("\n")}\n" \
              "Trace one of them by its full name."
      end

      # The path is part of the key: top-level code in two different spec files
      # is both called "(file scope)", and merging them would claim one caller
      # where there are two.
      def group(edges)
        edges.group_by { |edge| [edge.qualified_name, edge.type, edge.resolution, edge.reaches, edge.path] }
             .map { |key, group| to_relation(key, group) }
             .sort_by { |relation| [relation.qualified_name, relation.location] }
      end

      def to_relation(key, group)
        name, type, resolution, reaches, = key

        Relation.new(
          qualified_name: name, type: type, resolution: resolution, reaches: reaches,
          location: group.first.location, occurrences: group.size
        )
      end

      def index_missing_message
        "No index at #{@workspace.database_path}. Run `devintel index` first."
      end
    end
  end
end
