# frozen_string_literal: true

require "time"

module DevIntel
  module Database
    # Applies the index schema forward, one numbered migration at a time.
    #
    # The index is disposable but it is NOT dropped and recreated on every run:
    # incremental indexing depends on the previous run's file hashes surviving.
    class Migrator
      # Each entry is [version, SQL]. Append new versions; never edit a version
      # that has shipped.
      MIGRATIONS = [
        [
          1,
          <<~SQL
            CREATE TABLE files (
              id         INTEGER PRIMARY KEY AUTOINCREMENT,
              path       TEXT    NOT NULL UNIQUE,
              language   TEXT    NOT NULL,
              hash       TEXT    NOT NULL,
              size       INTEGER NOT NULL,
              updated_at TEXT    NOT NULL
            );

            CREATE INDEX index_files_on_language ON files (language);

            CREATE TABLE metadata (
              key   TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
          SQL
        ]
      ].freeze

      LATEST_VERSION = MIGRATIONS.map(&:first).max

      def initialize(connection)
        @connection = connection
      end

      def migrate!
        ensure_migrations_table

        pending.each do |version, sql|
          @connection.transaction do
            @connection.execute_batch(sql)
            @connection.execute(
              "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
              [version, Time.now.utc.iso8601]
            )
          end
        end

        current_version
      end

      def current_version
        ensure_migrations_table
        @connection.value("SELECT MAX(version) FROM schema_migrations") || 0
      end

      private

      def pending
        applied = applied_versions
        unknown = applied.reject { |version| version <= LATEST_VERSION }

        unless unknown.empty?
          raise SchemaTooNewError,
                "The index at #{@connection.path} was written by a newer DevIntel " \
                "(schema #{unknown.max}, this build understands #{LATEST_VERSION}). " \
                "Delete .devintel/ and re-run `devintel index`."
        end

        MIGRATIONS.reject { |migration| applied.include?(migration.first) }
      end

      def applied_versions
        @connection.execute("SELECT version FROM schema_migrations").map { |row| row["version"] }
      end

      def ensure_migrations_table
        @connection.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version    INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
          )
        SQL
      end
    end
  end
end
