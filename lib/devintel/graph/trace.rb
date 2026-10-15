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
        callees = graph.callees(name)

        Result.new(
          query: name,
          definitions: graph.definitions(name),
          callers: group(graph.callers(name)),
          # Untraceable edges are summarised rather than listed: they are real
          # relationships, but they lead outside what DevIntel can follow.
          callees: group(callees.select { |edge| Resolution.traceable?(edge.resolution) }),
          untraced: callees.reject { |edge| Resolution.traceable?(edge.resolution) }
                           .group_by(&:resolution).transform_values(&:size),
          tests: graph.tests(name)
        )
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
