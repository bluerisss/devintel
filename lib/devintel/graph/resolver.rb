# frozen_string_literal: true

module DevIntel
  module Graph
    # Turns the names recorded by the parser into edges of the symbol graph.
    #
    # Resolution runs once per indexing run, over every edge, after all files
    # are indexed. That is deliberate: an edge's meaning depends on symbols
    # defined in *other* files, so adding one file can resolve an edge written
    # months ago in another. Recomputing the whole set each run keeps the graph
    # correct without tracking cross-file invalidation.
    #
    # Nothing here guesses. Every outcome is one of the Resolution values, and
    # an edge that cannot be followed says so rather than pointing somewhere
    # plausible.
    class Resolver
      Stats = Data.define(:resolved, :by_resolution, :dropped_self_calls)

      SINGLETON_SEPARATOR = "."
      INSTANCE_SEPARATOR  = "#"

      # Scopes in which an implicit receiver means the class rather than an
      # instance of it.
      SINGLETON_SOURCES = [
        Parser::ExtractedSymbol::SINGLETON_METHOD,
        Parser::ExtractedSymbol::CLASS,
        Parser::ExtractedSymbol::MODULE
      ].freeze

      def initialize(connection)
        @connection = connection
      end

      # @return [Stats]
      def call
        names = symbol_names
        lookup = ConstantLookup.new(names)
        counts = Hash.new(0)
        dropped = []

        @connection.transaction do
          edges.each { |edge| apply(edge, lookup, names, counts, dropped) }
          delete(dropped)
        end

        Stats.new(resolved: counts.values.sum, by_resolution: counts, dropped_self_calls: dropped.size)
      end

      private

      def apply(edge, lookup, names, counts, dropped)
        outcome = resolve(edge, lookup, names)

        if outcome.nil?
          dropped << edge.fetch("id")
        else
          counts[outcome.fetch(:resolution)] += 1
          write(edge.fetch("id"), outcome)
        end
      end

      # Qualified name -> the lowest symbol id carrying it. A class reopened in
      # two files has one name and several rows; the lowest id is a stable
      # anchor, and queries match on the name rather than the id.
      def symbol_names
        rows = @connection.execute(
          "SELECT qualified_name, MIN(id) AS id FROM symbols GROUP BY qualified_name"
        )
        rows.to_h { |row| [row["qualified_name"], row["id"]] }
      end

      def edges
        @connection.execute(<<~SQL)
          SELECT r.id, r.type, r.source_scope, r.receiver_kind, r.receiver_name, r.target_name,
                 s.type AS source_type
          FROM symbol_references r
          LEFT JOIN symbols s ON s.id = r.source_symbol_id
        SQL
      end

      # @return [Hash, nil] nil means the edge should not be kept at all.
      def resolve(edge, lookup, names)
        return unresolved(Resolution::DYNAMIC) if edge["target_name"].nil?

        if edge["type"] == Parser::ExtractedReference::CALLS
          resolve_call(edge, lookup, names)
        else
          resolve_constant(edge, lookup, names)
        end
      end

      # INHERITS, INCLUDES, EXTENDS, PREPENDS, REFERENCES: the target is a constant.
      def resolve_constant(edge, lookup, names)
        qualified = lookup.call(edge["target_name"], edge["source_scope"])
        return unresolved(Resolution::NAMED) if qualified.nil?

        target(qualified, names, Resolution::RESOLVED)
      end

      def resolve_call(edge, lookup, names)
        case edge["receiver_kind"]
        when Parser::ExtractedReference::CONSTANT
          call_on_constant(edge, lookup, names, SINGLETON_SEPARATOR, Resolution::RESOLVED)
        when Parser::ExtractedReference::INSTANCE
          call_on_constant(edge, lookup, names, INSTANCE_SEPARATOR, Resolution::INFERRED)
        when Parser::ExtractedReference::SELF
          call_on_self(edge, names)
        else
          unresolved(Resolution::UNKNOWN_RECEIVER)
        end
      end

      def call_on_constant(edge, lookup, names, separator, resolution)
        owner = lookup.call(edge["receiver_name"], edge["source_scope"])
        return unresolved(Resolution::NAMED) if owner.nil?

        candidate = "#{owner}#{separator}#{edge['target_name']}"
        if names.key?(candidate)
          return target(candidate, names,
                        resolution).merge(receiver_qualified_name: owner)
        end

        # The class is ours, the method is not: `FileStore.new` is still
        # evidence that this code depends on FileStore.
        unresolved(Resolution::RECEIVER_ONLY).merge(receiver_qualified_name: owner)
      end

      # An implicit receiver means `self`. Inside a singleton method self is the
      # class, so the separator differs.
      #
      # When the method is not defined in that scope the edge is dropped, not
      # stored: a receiverless call that resolves nowhere is indistinguishable
      # from a Kernel method, a DSL macro, an attribute or a local variable.
      # Keeping those would bury the graph in `puts` and `expect` while
      # asserting a relationship the source does not state. The count is
      # reported so the omission stays visible.
      def call_on_self(edge, names)
        scope = edge["source_scope"].to_s
        return nil if scope.empty?

        candidate = "#{scope}#{self_separator(edge)}#{edge['target_name']}"
        return nil unless names.key?(candidate)

        target(candidate, names, Resolution::RESOLVED)
      end

      def self_separator(edge)
        SINGLETON_SOURCES.include?(edge["source_type"]) ? SINGLETON_SEPARATOR : INSTANCE_SEPARATOR
      end

      def target(qualified_name, names, resolution)
        {
          resolution: resolution,
          target_symbol_id: names[qualified_name],
          target_qualified_name: qualified_name,
          receiver_qualified_name: nil
        }
      end

      def unresolved(resolution)
        {
          resolution: resolution, target_symbol_id: nil,
          target_qualified_name: nil, receiver_qualified_name: nil
        }
      end

      def write(id, outcome)
        @connection.execute(
          "UPDATE symbol_references SET resolution = ?, target_symbol_id = ?, " \
          "target_qualified_name = ?, receiver_qualified_name = ? WHERE id = ?",
          [outcome[:resolution], outcome[:target_symbol_id],
           outcome[:target_qualified_name], outcome[:receiver_qualified_name], id]
        )
      end

      def delete(ids)
        ids.each_slice(500) do |chunk|
          placeholders = Array.new(chunk.size, "?").join(", ")
          @connection.execute("DELETE FROM symbol_references WHERE id IN (#{placeholders})", chunk)
        end
      end
    end
  end
end
