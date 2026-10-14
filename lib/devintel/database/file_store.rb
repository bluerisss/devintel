# frozen_string_literal: true

require "time"

module DevIntel
  module Database
    # Persistence for the `files` table.
    #
    # Infrastructure only: it knows SQL, never policy. Deciding *which* files
    # changed belongs to Index::Indexer.
    class FileStore
      # `content_hash` rather than `hash`: a Data member named `hash` would
      # override Object#hash and quietly break using the record as a Hash key.
      Record = Data.define(:id, :path, :language, :content_hash, :size)

      def initialize(connection)
        @connection = connection
      end

      # @return [Hash{String => Record}] every indexed file, keyed by path.
      def all_by_path
        rows = @connection.execute("SELECT id, path, language, hash, size FROM files")
        rows.to_h { |row| [row["path"], to_record(row)] }
      end

      def insert(path:, language:, hash:, size:, now: Time.now.utc)
        @connection.execute(
          "INSERT INTO files (path, language, hash, size, updated_at) VALUES (?, ?, ?, ?, ?)",
          [path, language, hash, size, now.iso8601]
        )
      end

      def update(id:, language:, hash:, size:, now: Time.now.utc)
        @connection.execute(
          "UPDATE files SET language = ?, hash = ?, size = ?, updated_at = ? WHERE id = ?",
          [language, hash, size, now.iso8601, id]
        )
      end

      def delete_by_paths(paths)
        return 0 if paths.empty?

        # Chunked so a repository with tens of thousands of deletions stays
        # under SQLite's bound-variable limit.
        paths.each_slice(500) do |chunk|
          placeholders = Array.new(chunk.size, "?").join(", ")
          @connection.execute("DELETE FROM files WHERE path IN (#{placeholders})", chunk)
        end
        paths.size
      end

      def count
        @connection.value("SELECT COUNT(*) FROM files")
      end

      private

      def to_record(row)
        Record.new(
          id: row["id"], path: row["path"], language: row["language"],
          content_hash: row["hash"], size: row["size"]
        )
      end
    end
  end
end
