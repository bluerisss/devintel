# frozen_string_literal: true

module DevIntel
  module Index
    # Decides whether a path is source DevIntel understands, and which language.
    #
    # Shared by file discovery and by the diff: a changed file has to be judged
    # the same way an indexed one was, or the two would disagree about what
    # counts as Ruby.
    module Language
      RUBY = "ruby"

      EXTENSIONS = %w[.rb .rake .gemspec .ru].freeze
      FILENAMES  = %w[Rakefile Gemfile Guardfile Capfile].freeze

      # Bytes read when sniffing an extensionless file's shebang.
      SHEBANG_LIMIT = 128

      # @param absolute_path [Pathname, nil] when given, an extensionless file
      #   is sniffed for a Ruby shebang; without it only the name is judged.
      # @return [String, nil]
      def self.of(filename, absolute_path = nil)
        return RUBY if EXTENSIONS.include?(File.extname(filename))
        return RUBY if FILENAMES.include?(filename)
        return RUBY if absolute_path && File.extname(filename).empty? && ruby_shebang?(absolute_path)

        nil
      end

      # Executables such as `bin/rails` or `bin/devintel` are Ruby source with
      # no extension, and missing them would leave real entry points out of the
      # index. Only extensionless files are opened, and only their first line,
      # so this costs a handful of short reads per repository.
      def self.ruby_shebang?(absolute_path)
        first_line = Pathname.new(absolute_path).open("rb") do |io|
          io.readline("\n", SHEBANG_LIMIT, chomp: true)
        end

        first_line.start_with?("#!") && first_line.include?(RUBY)
      rescue IOError, SystemCallError
        false
      end
    end
  end
end
