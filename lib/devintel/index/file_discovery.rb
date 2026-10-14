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

      RUBY_EXTENSIONS = %w[.rb .rake .gemspec .ru].freeze
      RUBY_FILENAMES  = %w[Rakefile Gemfile Guardfile Capfile].freeze

      # Bytes read when sniffing an extensionless file's shebang.
      SHEBANG_LIMIT = 128

      RUBY = "ruby"

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
          elsif (language = language_for(name, absolute))
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

      def language_for(filename, absolute_path)
        return RUBY if RUBY_EXTENSIONS.include?(File.extname(filename))
        return RUBY if RUBY_FILENAMES.include?(filename)
        return RUBY if File.extname(filename).empty? && ruby_shebang?(absolute_path)

        nil
      end

      # Executables such as `bin/rails` or `bin/devintel` are Ruby source with
      # no extension, and missing them would leave real entry points out of the
      # index. Only extensionless files are opened, and only their first line,
      # so this costs a handful of short reads per repository.
      def ruby_shebang?(absolute_path)
        first_line = absolute_path.open("rb") { |io| io.readline("\n", SHEBANG_LIMIT, chomp: true) }
        first_line.start_with?("#!") && first_line.include?(RUBY)
      rescue IOError, SystemCallError
        false
      end
    end
  end
end
