# frozen_string_literal: true

module DevIntel
  module Database
    # Persistence for the `symbol_references` table: the graph edges observed
    # in source. Edge types stay explicit (INHERITS, INCLUDES, ...) rather than
    # collapsing into a generic "related to".
    class ReferenceStore
      Record = Data.define(
        :id, :file_id, :source_symbol_id, :type, :source_scope, :receiver_kind, :receiver_name,
        :target_name, :target_symbol_id, :target_qualified_name, :receiver_qualified_name,
        :resolution, :line
      )

      INSERT = <<~SQL
        INSERT INTO symbol_references
          (file_id, source_symbol_id, type, source_scope, receiver_kind, receiver_name,
           target_name, resolution, line)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL

      def initialize(connection)
        @connection = connection
      end

      # @param symbol_ids [Array<Integer>] ids returned by SymbolStore#insert_all,
      #   indexed the same way as ExtractedReference#source_index.
      # Edges are stored unresolved: what they point at depends on symbols from
      # other files, so Graph::Resolver fills that in once indexing is done.
      def insert_all(file_id, references, symbol_ids)
        references.each do |reference|
          source_id = reference.source_index && symbol_ids[reference.source_index]
          @connection.execute(
            INSERT,
            [file_id, source_id, reference.type, reference.source_scope, reference.receiver_kind,
             reference.receiver_name, reference.target_name, Graph::Resolution::PENDING, reference.line]
          )
        end
      end

      def delete_for_file(file_id)
        @connection.execute("DELETE FROM symbol_references WHERE file_id = ?", [file_id])
      end

      def count
        @connection.value("SELECT COUNT(*) FROM symbol_references")
      end

      # @return [Hash{String => Integer}] edge count per type, largest first.
      def count_by_type
        rows = @connection.execute(
          "SELECT type, COUNT(*) AS total FROM symbol_references GROUP BY type ORDER BY total DESC, type"
        )
        rows.to_h { |row| [row["type"], row["total"]] }
      end

      # @return [Hash{String => Integer}] edge count per resolution, largest first.
      def count_by_resolution
        rows = @connection.execute(
          "SELECT resolution, COUNT(*) AS total FROM symbol_references " \
          "GROUP BY resolution ORDER BY total DESC, resolution"
        )
        rows.to_h { |row| [row["resolution"], row["total"]] }
      end

      def for_file(file_id)
        rows = @connection.execute(
          "SELECT * FROM symbol_references WHERE file_id = ? ORDER BY line, id", [file_id]
        )
        rows.map { |row| to_record(row) }
      end

      private

      def to_record(row)
        Record.new(
          id: row["id"], file_id: row["file_id"], source_symbol_id: row["source_symbol_id"],
          type: row["type"], source_scope: row["source_scope"], receiver_kind: row["receiver_kind"],
          receiver_name: row["receiver_name"], target_name: row["target_name"],
          target_symbol_id: row["target_symbol_id"], target_qualified_name: row["target_qualified_name"],
          receiver_qualified_name: row["receiver_qualified_name"],
          resolution: row["resolution"], line: row["line"]
        )
      end
    end
  end
end
