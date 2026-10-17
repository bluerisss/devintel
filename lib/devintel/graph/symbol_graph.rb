# frozen_string_literal: true

module DevIntel
  module Graph
    # Answers "what does this symbol relate to" from the stored graph.
    #
    # Queries match on qualified name rather than symbol id: a class reopened
    # in two files is one thing to a developer, and both definitions should
    # answer to the same name.
    class SymbolGraph
      # A symbol together with where it is written.
      Definition = Data.define(:qualified_name, :type, :path, :line_start, :line_end) do
        def location
          "#{path}:#{line_start}"
        end
      end

      # One end of a relationship, with the evidence for it.
      # `reaches` is the member of the traced symbol this edge lands on, which
      # tells apart two relationships from the same caller.
      Edge = Data.define(:type, :resolution, :qualified_name, :reaches, :path, :line) do
        def location
          "#{path}:#{line}"
        end

        def evidence_class
          Resolution.evidence_class(resolution)
        end
      end

      # `FileStore.new` resolves its receiver but not its method; naming the
      # member keeps that row distinguishable from one that resolved fully.
      REACHES = <<~SQL.strip
        COALESCE(
          r.target_qualified_name,
          r.receiver_qualified_name ||
            CASE r.receiver_kind WHEN 'instance' THEN '#' ELSE '.' END || r.target_name
        )
      SQL

      def initialize(connection)
        @connection = connection
      end

      # Every definition carrying this exact qualified name.
      def definitions(qualified_name)
        rows = @connection.execute(<<~SQL, [qualified_name])
          SELECT s.qualified_name, s.type, f.path, s.line_start, s.line_end
          FROM symbols s JOIN files f ON f.id = s.file_id
          WHERE s.qualified_name = ?
          ORDER BY f.path, s.line_start
        SQL
        rows.map { |row| to_definition(row) }
      end

      # Symbols whose name contains the query, nearest match first.
      #
      # A LIKE scan over the indexed `name` column rather than FTS5: symbol
      # names are short identifiers, not prose, and substring matching is what
      # a developer typing "PaymentSer" actually wants. FTS would add a second
      # copy of the data and a tokeniser that splits on the wrong boundaries.
      def search(query, limit: 50)
        pattern = "%#{escape_like(query)}%"

        prefix = "#{escape_like(query)}%"

        rows = @connection.execute(<<~SQL, [pattern, pattern, query, prefix, limit])
          SELECT s.qualified_name, s.type, f.path, s.line_start, s.line_end
          FROM symbols s JOIN files f ON f.id = s.file_id
          WHERE s.name LIKE ? ESCAPE '\\' OR s.qualified_name LIKE ? ESCAPE '\\'
          ORDER BY
            CASE WHEN s.name = ? THEN 0 WHEN s.name LIKE ? ESCAPE '\\' THEN 1 ELSE 2 END,
            LENGTH(s.qualified_name), s.qualified_name
          LIMIT ?
        SQL
        rows.map { |row| to_definition(row) }
      end

      # Definitions whose simple name matches, so a developer can type
      # `trace FileStore` instead of the full qualified name.
      def find_by_name(name)
        rows = @connection.execute(<<~SQL, [name])
          SELECT s.qualified_name, s.type, f.path, s.line_start, s.line_end
          FROM symbols s JOIN files f ON f.id = s.file_id
          WHERE s.name = ?
          ORDER BY s.qualified_name, f.path
        SQL
        rows.map { |row| to_definition(row) }
      end

      # The symbol itself plus everything defined inside it, so tracing a class
      # also covers its methods and constants.
      def members(qualified_name)
        rows = @connection.execute(<<~SQL, like_arguments(qualified_name))
          SELECT s.qualified_name, s.type, f.path, s.line_start, s.line_end
          FROM symbols s JOIN files f ON f.id = s.file_id
          WHERE #{name_matches('s.qualified_name')}
          ORDER BY s.qualified_name, f.path
        SQL
        rows.map { |row| to_definition(row) }
      end

      # Who reaches this symbol from outside it: edges whose resolved target,
      # or whose resolved receiver, is the symbol or one of its members.
      #
      # Calls between a symbol's own members are excluded. They are real, and
      # they already appear under callees; listing them here would answer "who
      # depends on this class" with the class itself.
      def callers(qualified_name)
        rows = @connection.execute(<<~SQL, like_arguments(qualified_name) * 3)
          SELECT r.type, r.resolution, f.path, r.line,
                 COALESCE(src.qualified_name, '(file scope)') AS qualified_name,
                 #{REACHES} AS reaches
          FROM symbol_references r
          JOIN files f ON f.id = r.file_id
          LEFT JOIN symbols src ON src.id = r.source_symbol_id
          WHERE ((#{name_matches('r.target_qualified_name')})
             OR (#{name_matches('r.receiver_qualified_name')}))
            -- Top-level code has no source symbol; NOT (NULL = ?) is NULL in
            -- SQL and would silently drop every caller written at file scope.
            AND (src.qualified_name IS NULL OR NOT (#{name_matches('src.qualified_name')}))
          ORDER BY f.path, r.line
        SQL
        rows.map { |row| to_edge(row) }
      end

      # What this symbol reaches, including edges DevIntel could not follow, so
      # the gaps in the picture are visible too.
      def callees(qualified_name)
        rows = @connection.execute(<<~SQL, like_arguments(qualified_name))
          SELECT r.type, r.resolution, f.path, r.line,
                 COALESCE(r.target_qualified_name, r.receiver_qualified_name,
                          r.target_name, '(dynamic)') AS qualified_name,
                 NULL AS reaches
          FROM symbol_references r
          JOIN files f ON f.id = r.file_id
          JOIN symbols src ON src.id = r.source_symbol_id
          WHERE #{name_matches('src.qualified_name')}
          ORDER BY f.path, r.line
        SQL
        rows.map { |row| to_edge(row) }
      end

      private

      # A symbol and everything nested in it: "User", "User#name", "User.find",
      # "User::ROLES".
      def name_matches(column)
        "#{column} = ? OR #{column} LIKE ? OR #{column} LIKE ? OR #{column} LIKE ?"
      end

      def like_arguments(qualified_name)
        [qualified_name, "#{qualified_name}#%", "#{qualified_name}.%", "#{qualified_name}::%"]
      end

      # `%` and `_` are wildcards in LIKE; a developer searching for "find_by"
      # means a literal underscore.
      def escape_like(value)
        value.gsub(/([%_\\])/) { "\\#{Regexp.last_match(1)}" }
      end

      def to_definition(row)
        Definition.new(
          qualified_name: row["qualified_name"], type: row["type"], path: row["path"],
          line_start: row["line_start"], line_end: row["line_end"]
        )
      end

      def to_edge(row)
        Edge.new(
          type: row["type"], resolution: row["resolution"],
          qualified_name: row["qualified_name"], reaches: row["reaches"],
          path: row["path"], line: row["line"]
        )
      end
    end
  end
end
