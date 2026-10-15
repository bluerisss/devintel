# frozen_string_literal: true

module DevIntel
  module Database
    # Persistence for the `symbols` table.
    class SymbolStore
      Record = Data.define(:id, :file_id, :type, :name, :qualified_name, :line_start, :line_end)

      INSERT = <<~SQL
        INSERT INTO symbols (file_id, type, name, qualified_name, line_start, line_end)
        VALUES (?, ?, ?, ?, ?, ?)
      SQL

      def initialize(connection)
        @connection = connection
      end

      # Inserts in order and returns the new ids positionally, so a caller can
      # map Parser::ExtractedReference#source_index onto a real symbol id.
      #
      # @return [Array<Integer>]
      def insert_all(file_id, symbols)
        symbols.map do |symbol|
          @connection.execute(
            INSERT,
            [file_id, symbol.type, symbol.name, symbol.qualified_name, symbol.line_start, symbol.line_end]
          )
          @connection.last_insert_id
        end
      end

      def delete_for_file(file_id)
        @connection.execute("DELETE FROM symbols WHERE file_id = ?", [file_id])
      end

      def count
        @connection.value("SELECT COUNT(*) FROM symbols")
      end

      # @return [Hash{String => Integer}] symbol count per type, largest first,
      #   so a reader can see what DevIntel actually understood.
      def count_by_type
        rows = @connection.execute(
          "SELECT type, COUNT(*) AS total FROM symbols GROUP BY type ORDER BY total DESC, type"
        )
        rows.to_h { |row| [row["type"], row["total"]] }
      end

      # @return [Array<Record>] ordered by position in the file.
      def for_file(file_id)
        rows = @connection.execute(
          "SELECT * FROM symbols WHERE file_id = ? ORDER BY line_start, id", [file_id]
        )
        rows.map { |row| to_record(row) }
      end

      def find_by_qualified_name(qualified_name)
        rows = @connection.execute(
          "SELECT * FROM symbols WHERE qualified_name = ? ORDER BY id", [qualified_name]
        )
        rows.map { |row| to_record(row) }
      end

      private

      def to_record(row)
        Record.new(
          id: row["id"], file_id: row["file_id"], type: row["type"], name: row["name"],
          qualified_name: row["qualified_name"], line_start: row["line_start"], line_end: row["line_end"]
        )
      end
    end
  end
end
