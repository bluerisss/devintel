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

      LATEST_VERSION = Migrations::LATEST_VERSION

      def initialize(connection)
        @connection = connection
      end

      # @return [Array<Integer>] versions applied by this call. A caller that
      #   has already indexed must treat a non-empty result as "the index can
      #   no longer answer what it used to" and re-analyse everything: file
      #   hashes survive migrations, so otherwise every file would look
      #   unchanged and the new tables would stay empty.
      def migrate!
        ensure_migrations_table

        pending.map do |version, sql|
          @connection.transaction do
            @connection.execute_batch(sql)
            @connection.execute(
              "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
              [version, Time.now.utc.iso8601]
            )
          end
          version
        end
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

        Migrations::ALL.reject { |migration| applied.include?(migration.first) }
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
