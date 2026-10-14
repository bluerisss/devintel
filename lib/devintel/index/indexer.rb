# frozen_string_literal: true

require "time"

module DevIntel
  module Index
    # Application service behind `devintel index`.
    #
    #   discover files -> hash contents -> compare with the stored index
    #                  -> write only what changed
    #
    # Unchanged files are never re-read beyond their hash, which is what later
    # milestones will build incremental parsing on top of.
    class Indexer
      # Outcome of one indexing run. `added + modified` is the work actually
      # performed; `unchanged` is the work skipped.
      Result = Data.define(
        :root, :database_path, :discovered, :added, :modified, :unchanged, :removed, :duration
      ) do
        def indexed
          added + modified
        end

        def changed
          added + modified + removed
        end
      end

      def initialize(workspace, discovery: nil, clock: Time.method(:now))
        @workspace = workspace
        @discovery = discovery || FileDiscovery.new(workspace.root)
        @clock = clock
      end

      # @param force [Boolean] re-write every file even if its hash is unchanged.
      def call(force: false)
        started_at = monotonic_now
        @workspace.prepare!

        files = @discovery.call
        counts = Database::Connection.open(@workspace.database_path) do |connection|
          Database::Migrator.new(connection).migrate!
          persist(connection, files, force: force)
        end

        build_result(files, counts, monotonic_now - started_at)
      end

      private

      def persist(connection, files, force:)
        store = Database::FileStore.new(connection)
        counts = Hash.new(0)

        connection.transaction do
          now = @clock.call.utc
          counts[:removed] = store.delete_by_paths(sync_all(store, files, counts, force: force, now: now))
          record_provenance(Database::MetadataStore.new(connection), now)
        end

        counts
      end

      # Writes every discovered file into the index.
      # @return [Array<String>] indexed paths that no longer exist on disk.
      def sync_all(store, files, counts, force:, now:)
        known = store.all_by_path

        files.each do |file|
          # Deleting as we go leaves `known` holding only the vanished paths.
          counts[sync(store, known.delete(file.path), file, force: force, now: now)] += 1
        end

        known.keys
      end

      # Writes one file into the index.
      # @return [Symbol] :added, :modified or :unchanged
      def sync(store, record, file, force:, now:)
        digest = ContentDigest.call(file.absolute_path)
        attributes = { language: file.language, hash: digest, size: file.absolute_path.size, now: now }

        if record.nil?
          store.insert(path: file.path, **attributes)
          :added
        elsif force || stale?(record, file, digest)
          store.update(id: record.id, **attributes)
          :modified
        else
          :unchanged
        end
      end

      def stale?(record, file, digest)
        record.content_hash != digest || record.language != file.language
      end

      # Lets later commands refuse to read an index they do not understand.
      def record_provenance(metadata, now)
        metadata["devintel_version"]  = VERSION
        metadata["schema_version"]    = Database::Migrator::LATEST_VERSION
        metadata["digest_algorithm"]  = ContentDigest::ALGORITHM
        metadata["last_indexed_at"]   = now.iso8601
      end

      def build_result(files, counts, duration)
        Result.new(
          root: @workspace.root,
          database_path: @workspace.database_path,
          discovered: files.size,
          added: counts[:added],
          modified: counts[:modified],
          unchanged: counts[:unchanged],
          removed: counts[:removed],
          duration: duration
        )
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
