# frozen_string_literal: true

# Builds a throwaway source tree on disk for a single example.
#
# Fixtures are written per-example rather than committed as a nested Git
# repository: a repository inside the repository cannot be checked in, and
# building the tree in the test keeps each example's expectations next to the
# files that produce them.
#
# Neither helper takes keyword arguments, so `with_repository("a.rb" => "")`
# passes the file map positionally instead of being parsed as keywords.
module SandboxRepository
  # A directory that is a Git repository root.
  # @yield [Pathname] the repository root
  def with_repository(files = {}, &block)
    with_directory(files) do |root|
      (root / ".git").mkpath
      block.call(root)
    end
  end

  # A directory that is *not* a Git repository.
  # @yield [Pathname] the directory
  def with_directory(files = {})
    Dir.mktmpdir("devintel-spec") do |tmp|
      root = Pathname.new(tmp).realpath
      files.each { |path, contents| write_file(root, path, contents) }
      yield root
    end
  end

  def write_file(root, path, contents = "")
    absolute = root.join(path)
    absolute.dirname.mkpath
    absolute.write(contents)
    absolute
  end

  def workspace_for(root)
    DevIntel::Workspace.new(root)
  end
end
