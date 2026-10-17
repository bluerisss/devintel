# frozen_string_literal: true

require "open3"

# Builds a real Git repository with real commits.
#
# SandboxRepository only creates a `.git` directory, which is enough for
# finding the repository root but not for reading a diff. These examples drive
# the actual git binary: the diff format, rename detection and `-z` quoting
# are exactly what could break, and a stubbed git would prove none of it.
module GitRepository
  BASE_BRANCH = "base"

  # @yield [Pathname, GitHelper]
  def with_git_repository(files = {})
    with_directory(files) do |root|
      git = GitHelper.new(root)
      git.init!
      git.commit_all!("initial") unless files.empty?
      yield root, git
    end
  end

  class GitHelper
    def initialize(root)
      @root = root
    end

    def init!
      run("init", "--quiet", "--initial-branch", BASE_BRANCH)
      run("config", "user.email", "devintel@example.com")
      run("config", "user.name", "DevIntel Spec")
      run("config", "commit.gpgsign", "false")
    end

    def commit_all!(message)
      run("add", "--all")
      run("commit", "--quiet", "--message", message)
    end

    def branch!(name)
      run("checkout", "--quiet", "-b", name)
    end

    def head
      run("rev-parse", "HEAD").strip
    end

    def run(*arguments)
      stdout, stderr, status = Open3.capture3("git", *arguments, chdir: @root.to_s)
      raise "git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

      stdout
    end
  end
end
