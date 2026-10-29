# frozen_string_literal: true

module DevIntel
  module Impact
    # Application service behind `devintel impact`.
    #
    #   changed symbols -> who calls them -> who calls those -> entry points
    #
    # It walks the graph `devintel index` already built; there is no second
    # dependency engine. Traversal follows only edges that resolve to a
    # definition in this repository, so every step is an observed call or a
    # labelled inference — never a name that happened to match.
    class Analyzer
      # Until depth is a flag, the limit is stated rather than silent: beyond
      # three hops almost everything in a codebase reaches almost everything.
      MAX_DEPTH = 3

      # A change to a widely used base class can reach most of a repository.
      # Truncating with a visible count beats printing thousands of rows.
      MAX_IMPACTED = 500

      # `via` is the symbol this one reaches, `relation` how it reaches it,
      # and `evidence` the exact line where that happens - which is inside
      # this symbol, so it is also the place to start reading.
      Impacted = Data.define(
        :qualified_name, :type, :path, :line_start, :line_end,
        :depth, :confidence, :via, :relation, :evidence
      ) do
        def direct?
          depth == 1
        end

        def location
          "#{path}:#{line_start}"
        end
      end

      Result = Data.define(
        :root, :base, :merge_base, :changed, :impacted, :entry_points,
        :tests, :untested, :unmapped, :truncated, :depth_limit
      ) do
        def direct
          impacted.select(&:direct?)
        end

        def indirect
          impacted.reject(&:direct?)
        end
      end

      def self.call(workspace, base:)
        new(workspace, base:).call
      end

      def initialize(workspace, base:)
        @workspace = workspace
        @base = base
      end

      def call
        diff = DevIntel::Diff::Analyzer.call(@workspace, base: @base)

        Database::Connection.open(@workspace.database_path) do |connection|
          build(diff, Graph::SymbolGraph.new(connection))
        end
      end

      private

      def build(diff, graph)
        changed = diff.symbols
        impacted = traverse(changed, graph)

        Result.new(
          root: @workspace.root, base: diff.base, merge_base: diff.merge_base,
          changed: changed, impacted: impacted,
          entry_points: entry_points(changed, impacted, graph),
          tests: TestCoverage.for(impact_names(changed, impacted), graph),
          untested: TestCoverage.untested(changed, graph),
          unmapped: diff.unmapped, truncated: impacted.size >= MAX_IMPACTED,
          depth_limit: MAX_DEPTH
        )
      end

      # Breadth-first so a symbol is recorded at the shortest distance from the
      # change, which is the strongest claim available about it.
      def traverse(changed, graph)
        seen = changed.to_set(&:qualified_name)
        frontier = changed.map { |symbol| [symbol.qualified_name, false] }
        impacted = []

        (1..MAX_DEPTH).each do |depth|
          frontier = step(frontier, depth, graph, seen, impacted)
          break if frontier.empty? || impacted.size >= MAX_IMPACTED
        end

        impacted.first(MAX_IMPACTED)
      end

      # @return [Array<Array(String, Boolean)>] the next frontier, each entry
      #   carrying whether any step that reached it was inferred.
      def step(frontier, depth, graph, seen, impacted)
        frontier.flat_map do |name, inferred_so_far|
          callers_of(name, graph).filter_map do |edge|
            next if seen.include?(edge.qualified_name)

            seen << edge.qualified_name
            inferred = inferred_so_far || !Graph::Resolution::FACT.include?(edge.resolution)
            impacted << impacted_from(edge, name, depth, inferred, graph)
            [edge.qualified_name, inferred]
          end
        end
      end

      # Tests are reported in their own section; counting a spec as an
      # impacted caller would double as evidence that production code is
      # affected, which it is not.
      def callers_of(name, graph)
        graph.callers(name).reject { |edge| Graph::TestFiles.test?(edge.path) || file_scope?(edge) }
      end

      # Top-level code has no symbol to continue the walk from.
      def file_scope?(edge)
        edge.qualified_name == Graph::SymbolGraph::FILE_SCOPE
      end

      def impacted_from(edge, via, depth, inferred, graph)
        Impacted.new(
          **definition_fields(edge, graph),
          depth: depth, confidence: Confidence.for(depth:, inferred:),
          via: via, relation: edge.type.downcase, evidence: "#{edge.path}:#{edge.line}"
        )
      end

      # Where the impacted symbol is defined. A caller is normally a symbol in
      # the index; falling back to the call site keeps the row useful if it is
      # somehow not.
      def definition_fields(edge, graph)
        definition = graph.definitions(edge.qualified_name).first

        {
          qualified_name: edge.qualified_name, type: definition&.type || "unknown",
          path: definition&.path || edge.path,
          line_start: definition&.line_start || edge.line,
          line_end: definition&.line_end || edge.line
        }
      end

      def impact_names(changed, impacted)
        (changed.map(&:qualified_name) + impacted.map(&:qualified_name)).uniq
      end

      # Nothing outside the tests calls these: either behaviour enters the
      # system here (a controller action, a job, a rake task), or nothing
      # reaches the code at all. DevIntel cannot tell those apart statically,
      # and says so rather than claiming one.
      def entry_points(changed, impacted, graph)
        candidates = changed.map(&:qualified_name) + impacted.map(&:qualified_name)

        candidates.uniq.select { |name| callers_of(name, graph).empty? }.sort
      end
    end
  end
end
