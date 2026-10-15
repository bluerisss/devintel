# frozen_string_literal: true

RSpec.describe DevIntel::Index::Indexer do
  def index(root, force: false)
    described_class.new(workspace_for(root)).call(force: force)
  end

  def stored_files(root)
    DevIntel::Database::Connection.open(workspace_for(root).database_path) do |connection|
      DevIntel::Database::FileStore.new(connection).all_by_path
    end
  end

  it "indexes every discovered file on a first run" do
    with_repository("app/models/user.rb" => "class User; end\n", "lib/a.rb" => "A = 1\n") do |root|
      result = index(root)

      expect(result.discovered).to eq(2)
      expect(result.added).to eq(2)
      expect(result.modified).to eq(0)
      expect(result.unchanged).to eq(0)
      expect(result.parsed).to eq(2)
    end
  end

  it "stores repository-relative paths, content hash, size and language" do
    source = "class User; end\n"
    with_repository("app/models/user.rb" => source) do |root|
      index(root)

      record = stored_files(root).fetch("app/models/user.rb")
      expect(record.language).to eq("ruby")
      expect(record.content_hash).to eq(Digest::SHA256.hexdigest(source))
      expect(record.size).to eq(source.bytesize)
    end
  end

  it "creates the database inside .devintel/" do
    with_repository("a.rb" => "") do |root|
      index(root)

      expect(root.join(".devintel/index.sqlite")).to exist
    end
  end

  it "keeps the index out of the target repository's history" do
    with_repository("a.rb" => "") do |root|
      index(root)

      expect(root.join(".devintel/.gitignore").read).to include("*")
    end
  end

  it "skips files whose content has not changed" do
    with_repository("a.rb" => "A = 1\n") do |root|
      index(root)

      result = index(root)

      expect(result.unchanged).to eq(1)
      expect(result.parsed).to eq(0)
      expect(result.removed).to eq(0)
    end
  end

  it "detects a file whose content changed" do
    with_repository("a.rb" => "A = 1\n") do |root|
      index(root)
      write_file(root, "a.rb", "A = 2\n")

      result = index(root)

      expect(result.modified).to eq(1)
      expect(result.added).to eq(0)
      expect(stored_files(root).fetch("a.rb").content_hash).to eq(Digest::SHA256.hexdigest("A = 2\n"))
    end
  end

  it "ignores a touched file whose content is identical" do
    with_repository("a.rb" => "A = 1\n") do |root|
      index(root)
      FileUtils.touch(root.join("a.rb"), mtime: Time.now + 60)

      expect(index(root).unchanged).to eq(1)
    end
  end

  it "detects a newly added file without re-indexing the rest" do
    with_repository("a.rb" => "A = 1\n") do |root|
      index(root)
      write_file(root, "b.rb", "B = 2\n")

      result = index(root)

      expect(result.added).to eq(1)
      expect(result.unchanged).to eq(1)
    end
  end

  it "removes files that are gone from disk" do
    with_repository("a.rb" => "A = 1\n", "b.rb" => "B = 2\n") do |root|
      index(root)
      root.join("b.rb").delete

      result = index(root)

      expect(result.removed).to eq(1)
      expect(stored_files(root).keys).to eq(["a.rb"])
    end
  end

  it "re-writes unchanged files when forced" do
    with_repository("a.rb" => "A = 1\n") do |root|
      index(root)

      result = index(root, force: true)

      expect(result.modified).to eq(1)
      expect(result.unchanged).to eq(0)
    end
  end

  it "does not drop the database between runs" do
    with_repository("a.rb" => "A = 1\n") do |root|
      index(root)
      id = stored_files(root).fetch("a.rb").id

      index(root)

      expect(stored_files(root).fetch("a.rb").id).to eq(id)
    end
  end

  it "records provenance metadata for later commands to verify" do
    with_repository("a.rb" => "") do |root|
      index(root)

      metadata = DevIntel::Database::Connection.open(workspace_for(root).database_path) do |connection|
        DevIntel::Database::MetadataStore.new(connection).to_h
      end

      expect(metadata).to include(
        "devintel_version" => DevIntel::VERSION,
        "schema_version" => DevIntel::Database::Migrator::LATEST_VERSION.to_s,
        "digest_algorithm" => "sha256"
      )
      expect(metadata["last_indexed_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end
  end

  it "never writes outside .devintel/" do
    with_repository("a.rb" => "A = 1\n") do |root|
      before = root.children.map(&:basename).map(&:to_s).sort

      index(root)

      expect(root.children.map(&:basename).map(&:to_s).sort - before).to eq([".devintel"])
    end
  end

  it "reports an empty repository without failing" do
    with_repository do |root|
      result = index(root)

      expect(result.discovered).to eq(0)
      expect(result.parsed).to eq(0)
    end
  end
end
