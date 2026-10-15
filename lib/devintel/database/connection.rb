# frozen_string_literal: true

require "sqlite3"
require "pathname"
require "fileutils"

module DevIntel
  module Database
    # Thin wrapper over the SQLite handle used for the local index.
    #
    # The index is a local, single-user, disposable artefact, which is why
    # SQLite is enough and no ORM is involved: the schema is small and the
    # queries are hand-written and explicit.
    class Connection
      attr_reader :path

      def self.open(path)
        connection = new(path)
        return connection unless block_given?

        begin
          yield connection
        ensure
          connection.close
        end
      end

      def initialize(path)
        @path = Pathname.new(path).expand_path
        FileUtils.mkdir_p(@path.dirname)
        @db = SQLite3::Database.new(@path.to_s)
        configure
      end

      def execute(sql, bind_vars = [])
        @db.execute(sql, bind_vars)
      end

      def execute_batch(sql)
        @db.execute_batch(sql)
      end

      # @return [Object, nil] first column of the first row.
      def value(sql, bind_vars = [])
        @db.get_first_value(sql, bind_vars)
      end

      # Indexing writes many rows; wrapping them in one transaction keeps the
      # index consistent (a crashed run leaves the previous index intact) and is
      # an order of magnitude faster than autocommitting each row.
      def transaction(&)
        @db.transaction(&)
      end

      def last_insert_id
        @db.last_insert_row_id
      end

      def close
        @db.close unless @db.closed?
      end

      private

      def configure
        @db.results_as_hash = true
        # WAL lets a reader (a future `devintel map` server) query the index
        # while an indexing run is writing.
        @db.execute("PRAGMA journal_mode = WAL")
        @db.execute("PRAGMA foreign_keys = ON")
        @db.execute("PRAGMA synchronous = NORMAL")
      end
    end
  end
end
