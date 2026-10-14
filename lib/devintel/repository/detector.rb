# frozen_string_literal: true

require "pathname"

module DevIntel
  module Repository
    # Finds the Git repository root by walking up the directory tree.
    #
    # This is deliberately pure Ruby rather than `git rev-parse`: it keeps
    # DevIntel usable without the git binary on PATH, makes the result
    # deterministic, and lets the test suite use plain fixture directories.
    class Detector
      def initialize(start_path = Dir.pwd)
        @start_path = Pathname.new(start_path).expand_path
      end

      # @return [Pathname, nil]
      def root
        candidate = @start_path.directory? ? @start_path : @start_path.dirname

        loop do
          # `.git` is a directory in a normal clone and a file in a worktree or
          # submodule, so test for existence rather than for a directory.
          return candidate if candidate.join(".git").exist?

          parent = candidate.parent
          return nil if parent == candidate

          candidate = parent
        end
      end

      # @raise [RepositoryNotFoundError] when +start_path+ is outside any repository.
      def root!
        root || raise(
          RepositoryNotFoundError,
          "#{@start_path} is not inside a Git repository. Run DevIntel from a repository checkout."
        )
      end
    end
  end
end
