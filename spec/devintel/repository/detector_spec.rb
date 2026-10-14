# frozen_string_literal: true

RSpec.describe DevIntel::Repository::Detector do
  it "returns the repository root when started at the root" do
    with_repository do |root|
      expect(described_class.new(root).root!).to eq(root)
    end
  end

  it "walks up from a nested directory to the repository root" do
    with_repository("app/services/user_service.rb" => "") do |root|
      nested = root.join("app/services")

      expect(described_class.new(nested).root!).to eq(root)
    end
  end

  it "accepts a file path and resolves from its directory" do
    with_repository("app/models/user.rb" => "") do |root|
      expect(described_class.new(root.join("app/models/user.rb")).root!).to eq(root)
    end
  end

  it "detects a worktree or submodule, where .git is a file" do
    with_directory do |root|
      write_file(root, ".git", "gitdir: /elsewhere/.git/worktrees/feature\n")

      expect(described_class.new(root).root!).to eq(root)
    end
  end

  it "returns nil outside a repository" do
    with_directory do |root|
      expect(described_class.new(root).root).to be_nil
    end
  end

  it "raises a readable error when asked for a root outside a repository" do
    with_directory do |root|
      expect { described_class.new(root).root! }
        .to raise_error(DevIntel::RepositoryNotFoundError, /not inside a Git repository/)
    end
  end
end
