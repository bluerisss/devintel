# frozen_string_literal: true

require "time"

module DevIntel
  module Index
    # Application service behind `devintel index`.
    #
    #   discover files -> hash contents -> compare with the stored index
    #                  -> parse and re-analyse only what changed
    #
    # A file whose content hash is unchanged is never parsed, which is what
    # keeps re-indexing a large repository cheap.
    class Indexer
      # Outcome of one indexing run. The file counts describe *this run*; the
      # symbol, reference and parse-error counts describe the resulting index
      # as a whole, so a no-op run still reports what the index holds.
      Result = Data.define(
        :root, :database_path, :discovered, :added, :modified, :unchanged, :removed,
        :symbols, :symbol_types, :references, :reference_types, :resolutions,
        :unattributed_self_calls, :parse_error_paths, :duration
      ) do
        # Edges that point at a definition in this repository and can therefore
        # be followed; the rest are real relationships leading outside it.
        def traceable_references
          resolutions.select { |resolution, _| Graph::Resolution.traceable?(resolution) }.values.sum
        end

        def untraceable_references
          references - traceable_references
        end

        # Files actually read and parsed this run.
        def parsed
          added + modified
        end

        def parse_errors
          parse_error_paths.size
        end
      end

      # The stores one indexing run writes through.
      Stores = Data.define(:files, :symbols, :references, :analyzer)

      def initialize(workspace, discovery: nil, clock: Time.method(:now))
        @workspace = workspace
        @discovery = discovery || FileDiscovery.new(workspace.root)
        @clock = clock
      end

      # @param force [Boolean] re-index every file even if its hash is unchanged.
      def call(force: false)
        started_at = monotonic_now
        @workspace.prepare!

        files = @discovery.call
        totals = Database::Connection.open(@workspace.database_path) do |connection|
          write(connection, files, force: force)
        end

        build_result(files, totals, monotonic_now - started_at)
      end

      private

      def write(connection, files, force:)
        # Applying a migration means the index can now hold more than it did,
        # so everything must be re-analysed: hashes survive migrations and
        # every file would otherwise look unchanged.
        migrated = Database::Migrator.new(connection).migrate!.any?
        counts = persist(connection, files, force: force || migrated)

        # Resolution spans files, so it runs once over the whole graph after
        # every file has been written, not per file.
        stats = Graph::Resolver.new(connection).call

        counts.merge(Totals.call(connection))
              .merge(unattributed_self_calls: stats.dropped_self_calls)
      end

      def persist(connection, files, force:)
        stores = open_stores(connection)
        counts = Hash.new(0)

        connection.transaction do
          now = @clock.call.utc
          orphaned = sync_all(stores, files, counts, force: force, now: now)
          counts[:removed] = stores.files.delete_by_paths(orphaned)
          record_provenance(Database::MetadataStore.new(connection), now)
        end

        counts
      end

      def open_stores(connection)
        files = Database::FileStore.new(connection)
        symbols = Database::SymbolStore.new(connection)
        references = Database::ReferenceStore.new(connection)

        Stores.new(files: files, symbols: symbols, references: references,
                   analyzer: FileAnalyzer.new(files, symbols, references))
      end

      # Writes every discovered file into the index.
      # @return [Array<String>] indexed paths that no longer exist on disk.
      def sync_all(stores, files, counts, force:, now:)
        known = stores.files.all_by_path

        files.each do |file|
          # Deleting as we go leaves `known` holding only the vanished paths.
          counts[sync(stores, known.delete(file.path), file, force: force, now: now)] += 1
        end

        known.keys
      end

      # Writes one file into the index.
      # @return [Symbol] :added, :modified or :unchanged
      def sync(stores, record, file, force:, now:)
        digest = ContentDigest.call(file.absolute_path)
        attributes = file_attributes(file, digest, now)

        if record.nil?
          file_id = stores.files.insert(path: file.path, **attributes)
          outcome = :added
        elsif force || stale?(record, file, digest)
          file_id = record.id
          stores.files.update(id: file_id, **attributes)
          outcome = :modified
        else
          return :unchanged
        end

        stores.analyzer.call(file_id, file)
        outcome
      end

      def file_attributes(file, digest, now)
        { language: file.language, hash: digest, size: file.absolute_path.size, now: now }
      end

      def stale?(record, file, digest)
        record.content_hash != digest || record.language != file.language
      end

      # Lets later commands refuse to read an index they do not understand.
      def record_provenance(metadata, now)
        metadata["devintel_version"] = VERSION
        metadata["schema_version"] = Database::Migrator::LATEST_VERSION
        metadata["digest_algorithm"] = ContentDigest::ALGORITHM
        metadata["last_indexed_at"] = now.iso8601
      end

      def build_result(files, totals, duration)
        Result.new(
          root: @workspace.root,
          database_path: @workspace.database_path,
          discovered: files.size,
          added: totals[:added], modified: totals[:modified],
          unchanged: totals[:unchanged], removed: totals[:removed],
          symbols: totals[:symbols], symbol_types: totals[:symbol_types],
          references: totals[:references], reference_types: totals[:reference_types],
          resolutions: totals[:resolutions],
          unattributed_self_calls: totals[:unattributed_self_calls],
          parse_error_paths: totals[:parse_error_paths],
          duration: duration
        )
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
