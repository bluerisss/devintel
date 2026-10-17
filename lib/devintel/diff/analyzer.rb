# frozen_string_literal: true

module DevIntel
  module Diff
    # Application service behind `devintel diff`.
    #
    #   merge base -> changed files -> changed lines -> the symbols on them
    #
    # The index describes the working tree, so a file that has changed since
    # the last `devintel index` cannot be mapped: its stored line numbers
    # describe different code. Rather than reporting the symbols that used to
    # occupy those lines, such a file is listed as stale. A wrong symbol cited
    # as evidence is worse than an admitted gap.
    class Analyzer
      # Why a changed file did or did not yield symbols.
      MAPPED       = "mapped"
      NOT_RUBY     = "not Ruby"
      NOT_INDEXED  = "not in the index"
      STALE        = "changed since the last index"
      DELETED      = "deleted"
      NO_SYMBOL    = "changed outside any symbol"

      FileChange = Data.define(:path, :status, :lines, :state, :symbols) do
        def mapped?
          state == MAPPED
        end
      end

      ChangedSymbol = Data.define(:qualified_name, :type, :path, :line_start, :line_end) do
        def location
          "#{path}:#{line_start}-#{line_end}"
        end
      end

      Result = Data.define(:root, :base, :merge_base, :files) do
        def symbols
          files.flat_map(&:symbols).uniq.sort_by(&:qualified_name)
        end

        def unmapped
          files.reject(&:mapped?)
        end
      end

      def self.call(workspace, base:)
        new(workspace, base: base).call
      end

      def initialize(workspace, base:, git: nil)
        @workspace = workspace
        @base = base
        @git = git || Repository::Git.new(workspace.root)
      end

      def call
        raise IndexNotFoundError, index_missing_message unless @workspace.database_path.exist?

        merge_base = @git.merge_base(@base)
        changes = tracked_changes(merge_base) + untracked_changes

        Database::Connection.open(@workspace.database_path) do |connection|
          Result.new(root: @workspace.root, base: @base, merge_base: merge_base,
                     files: changes.map { |change| examine(change, connection) }.sort_by(&:path))
        end
      end

      private

      def tracked_changes(merge_base)
        lines = @git.changed_lines(merge_base)

        @git.changed_files(merge_base).map do |file|
          { path: file.path, status: file.status, lines: lines.fetch(file.path, []), deleted: file.deleted? }
        end
      end

      # A file Git has never seen has no diff, but every line of it is new.
      def untracked_changes
        @git.untracked_files.filter_map do |path|
          absolute = @workspace.root.join(path)
          next unless Index::Language.of(File.basename(path), absolute)

          { path: path, status: Repository::Git::ChangedFile::ADDED,
            lines: [1..line_count(absolute)], deleted: false }
        end
      end

      def line_count(absolute)
        absolute.each_line.count
      rescue SystemCallError
        0
      end

      def examine(change, connection)
        state, symbols = classify(change, connection)

        FileChange.new(path: change[:path], status: change[:status], lines: change[:lines],
                       state: state, symbols: symbols)
      end

      # @return [Array(String, Array<ChangedSymbol>)]
      def classify(change, connection)
        return [DELETED, []] if change[:deleted]
        return [NOT_RUBY, []] unless ruby?(change[:path])

        record = Database::FileStore.new(connection).all_by_path[change[:path]]
        return [NOT_INDEXED, []] if record.nil?
        return [STALE, []] if stale?(change[:path], record)

        symbols = symbols_on(change, record, connection)
        symbols.empty? ? [NO_SYMBOL, []] : [MAPPED, symbols]
      end

      def ruby?(path)
        absolute = @workspace.root.join(path)

        !Index::Language.of(File.basename(path), absolute.exist? ? absolute : nil).nil?
      end

      def stale?(path, record)
        absolute = @workspace.root.join(path)
        return true unless absolute.exist?

        Index::ContentDigest.call(absolute) != record.content_hash
      end

      def symbols_on(change, record, connection)
        defined_symbols = Database::SymbolStore.new(connection).for_file(record.id)
        path = change[:path]

        touched_lines(change, path)
          .filter_map { |line| innermost(defined_symbols, line) }
          .uniq
          .map { |symbol| to_changed_symbol(symbol, path) }
      end

      def touched_lines(change, path)
        source = source_lines(path)

        change[:lines].flat_map(&:to_a).reject { |line| blank?(source, line) }
      end

      # A blank line carries no behaviour, and the innermost symbol spanning
      # one is usually the whole enclosing class - so an added empty line
      # between two methods would otherwise report the class as changed.
      # Comments are deliberately *not* filtered: a magic comment or a RuboCop
      # directive does change how the file behaves.
      def blank?(source, line)
        source.fetch(line - 1, "").strip.empty?
      end

      def source_lines(path)
        @workspace.root.join(path).readlines(chomp: true)
      rescue SystemCallError
        []
      end

      # The smallest definition spanning the line. A change inside a method
      # belongs to that method, not to the class that happens to contain it.
      def innermost(symbols, line)
        symbols.select { |symbol| line.between?(symbol.line_start, symbol.line_end) }
               .min_by { |symbol| symbol.line_end - symbol.line_start }
      end

      def to_changed_symbol(symbol, path)
        ChangedSymbol.new(
          qualified_name: symbol.qualified_name, type: symbol.type, path: path,
          line_start: symbol.line_start, line_end: symbol.line_end
        )
      end

      def index_missing_message
        "No index at #{@workspace.database_path}. Run `devintel index` first."
      end
    end
  end
end
