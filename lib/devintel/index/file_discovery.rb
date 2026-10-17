# frozen_string_literal: true

require "pathname"

module DevIntel
  module Index
    # Walks a repository and returns the source files DevIntel should index.
    #
    # The walk is pure Ruby rather than `git ls-files` so that discovery works
    # on a dirty working tree, on files Git has never seen, and on plain fixture
    # directories in the test suite.
    class FileDiscovery
      # Directory names skipped at any depth. Kept explicit and small: an
      # over-eager ignore list silently hides code, which is worse than
      # indexing a few files nobody asked for.
      IGNORED_DIRECTORIES = %w[.git .devintel node_modules tmp log vendor].freeze

      def initialize(root, ignored_directories: IGNORED_DIRECTORIES)
        @root = Pathname.new(root).expand_path
        @ignored_directories = ignored_directories.to_set
      end

      # @return [Array<SourceFile>] sorted by path, so indexing runs are deterministic.
      def call
        files = []
        walk(@root, "", files)
        files.sort_by(&:path)
      end

      private

      def walk(directory, relative_prefix, files)
        each_child(directory) do |name|
          absolute = directory.join(name)
          relative = relative_prefix.empty? ? name : "#{relative_prefix}/#{name}"

          # Symlinks are skipped: they can point outside the repository or form
          # cycles, and following them would index the same file twice.
          next if absolute.symlink?

          if absolute.directory?
            next if @ignored_directories.include?(name)

            walk(absolute, relative, files)
          elsif (language = Language.of(name, absolute))
            files << SourceFile.new(path: relative, language: language, absolute_path: absolute)
          end
        end
      end

      def each_child(directory)
        directory.children(false).each { |child| yield child.to_s }
      rescue Errno::EACCES, Errno::ENOENT
        # An unreadable or vanished directory is skipped rather than aborting
        # the whole run; the rest of the repository is still worth indexing.
        nil
      end
    end
  end
end
