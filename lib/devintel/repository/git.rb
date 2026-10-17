# frozen_string_literal: true

require "open3"

module DevIntel
  module Repository
    # Reads history from the Git CLI.
    #
    # Repository::Detector finds the repository root in pure Ruby because that
    # must work without git installed. Reading a diff cannot: reimplementing
    # Git's pack format and rename detection to avoid one subprocess would be
    # absurd. So this is where DevIntel shells out, and the rules are:
    #
    #   - arguments are passed as an argv array, never interpolated into a
    #     shell string, so a base ref like `;rm -rf /` is an unknown ref and
    #     nothing more;
    #   - `--no-pager` and an explicit `core.quotepath=false` keep the output
    #     machine-readable regardless of the user's git configuration;
    #   - `-z` is used wherever git offers it, so paths containing spaces or
    #     non-ASCII characters survive intact.
    class Git
      class CommandFailed < Error; end

      # A path Git reports as changed, with how it changed.
      class ChangedFile < Data.define(:path, :old_path, :status)
        ADDED    = "added"
        MODIFIED = "modified"
        DELETED  = "deleted"
        RENAMED  = "renamed"

        STATUSES = [ADDED, MODIFIED, DELETED, RENAMED].freeze

        def deleted?
          status == DELETED
        end
      end

      STATUS_NAMES = {
        "A" => ChangedFile::ADDED, "M" => ChangedFile::MODIFIED, "D" => ChangedFile::DELETED,
        "R" => ChangedFile::RENAMED, "C" => ChangedFile::ADDED, "T" => ChangedFile::MODIFIED
      }.freeze

      def initialize(root)
        @root = Pathname.new(root)
      end

      # @return [String] the commit where this branch left the base.
      #
      # Merge base rather than the base ref itself: on a feature branch,
      # `git diff origin/develop` also reports everything that landed on
      # develop after the branch point, as though the developer had reverted
      # it. The merge base answers the question actually being asked — what
      # have *I* changed.
      def merge_base(base)
        verify_ref!(base)

        run("merge-base", base, "HEAD").strip
      rescue CommandFailed
        raise Error, "#{base} and HEAD share no common history, so there is nothing to compare."
      end

      def verify_ref!(ref)
        run("rev-parse", "--verify", "--quiet", "#{ref}^{commit}")
      rescue CommandFailed
        raise Error, "Unknown base `#{ref}`. Pass an existing commit, branch or tag with --base."
      end

      # @return [Array<ChangedFile>]
      def changed_files(from)
        parse_name_status(run("diff", "--name-status", "-z", "-M", from))
      end

      # Files Git has never seen. They have no diff, but a brand new service
      # is a change, and leaving it out would silently answer "nothing to see".
      # @return [Array<String>]
      def untracked_files
        run("ls-files", "--others", "--exclude-standard", "-z").split("\0").reject(&:empty?)
      end

      # Changed line numbers in the *new* version of each file, which is what
      # the index describes.
      # @return [Hash{String => Array<Range>}]
      def changed_lines(from)
        Diff::HunkParser.call(run("diff", "--unified=0", "--no-color", "--no-ext-diff", "-M", from))
      end

      def head
        run("rev-parse", "--short", "HEAD").strip
      end

      private

      def run(*arguments)
        stdout, stderr, status = Open3.capture3(
          "git", "-c", "core.quotepath=false", "--no-pager", *arguments, chdir: @root.to_s
        )
        raise CommandFailed, "git #{arguments.first}: #{stderr.strip}" unless status.success?

        stdout
      rescue Errno::ENOENT
        raise Error, "git is not installed, or not on PATH. DevIntel needs it to read a diff."
      end

      # `-z` output is NUL-separated: "M\0path\0", and for a rename
      # "R100\0old\0new\0".
      def parse_name_status(output)
        tokens = output.split("\0").reject(&:empty?)
        files = []

        until tokens.empty?
          code = tokens.shift
          status = STATUS_NAMES.fetch(code[0], ChangedFile::MODIFIED)
          files << build_change(status, tokens)
        end

        files
      end

      def build_change(status, tokens)
        if status == ChangedFile::RENAMED
          old_path = tokens.shift
          ChangedFile.new(path: tokens.shift, old_path: old_path, status: status)
        else
          ChangedFile.new(path: tokens.shift, old_path: nil, status: status)
        end
      end
    end
  end
end
