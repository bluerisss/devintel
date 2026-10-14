# frozen_string_literal: true

RSpec.describe DevIntel::Workspace do
  it "derives its paths from the repository root" do
    with_repository do |root|
      workspace = described_class.new(root)

      expect(workspace.directory).to eq(root.join(".devintel"))
      expect(workspace.database_path).to eq(root.join(".devintel/index.sqlite"))
    end
  end

  it "discovers the repository root from a nested directory" do
    with_repository("app/models/user.rb" => "") do |root|
      expect(described_class.discover(root.join("app/models")).root).to eq(root)
    end
  end

  it "fails clearly when there is no repository" do
    with_directory do |dir|
      expect { described_class.discover(dir) }.to raise_error(DevIntel::RepositoryNotFoundError)
    end
  end

  it "makes paths repository-relative" do
    with_repository do |root|
      workspace = described_class.new(root)

      expect(workspace.relative_path(root.join("app/models/user.rb"))).to eq("app/models/user.rb")
    end
  end

  it "does not overwrite an existing .devintel/.gitignore" do
    with_repository do |root|
      workspace = described_class.new(root).prepare!
      workspace.directory.join(".gitignore").write("custom\n")

      workspace.prepare!

      expect(workspace.directory.join(".gitignore").read).to eq("custom\n")
    end
  end
end
