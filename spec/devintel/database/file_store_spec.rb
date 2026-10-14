# frozen_string_literal: true

RSpec.describe DevIntel::Database::FileStore do
  around do |example|
    with_directory do |root|
      DevIntel::Database::Connection.open(root.join("index.sqlite")) do |connection|
        DevIntel::Database::Migrator.new(connection).migrate!
        @connection = connection
        example.run
      end
    end
  end

  subject(:store) { described_class.new(@connection) }

  it "round-trips a file record keyed by path" do
    store.insert(path: "app/models/user.rb", language: "ruby", hash: "abc123", size: 42)

    record = store.all_by_path.fetch("app/models/user.rb")
    expect(record.language).to eq("ruby")
    expect(record.content_hash).to eq("abc123")
    expect(record.size).to eq(42)
  end

  it "updates an existing record in place, keeping its id" do
    store.insert(path: "a.rb", language: "ruby", hash: "old", size: 1)
    id = store.all_by_path.fetch("a.rb").id

    store.update(id: id, language: "ruby", hash: "new", size: 2)

    record = store.all_by_path.fetch("a.rb")
    expect(record.id).to eq(id)
    expect(record.content_hash).to eq("new")
  end

  it "deletes the given paths and leaves the rest alone" do
    store.insert(path: "a.rb", language: "ruby", hash: "a", size: 1)
    store.insert(path: "b.rb", language: "ruby", hash: "b", size: 1)

    expect(store.delete_by_paths(["a.rb"])).to eq(1)
    expect(store.all_by_path.keys).to eq(["b.rb"])
  end

  it "treats an empty delete as a no-op" do
    store.insert(path: "a.rb", language: "ruby", hash: "a", size: 1)

    expect(store.delete_by_paths([])).to eq(0)
    expect(store.count).to eq(1)
  end

  it "deletes more paths than SQLite allows bound variables in one statement" do
    paths = Array.new(1200) { |i| "file_#{i}.rb" }
    paths.each { |path| store.insert(path: path, language: "ruby", hash: "h", size: 1) }

    store.delete_by_paths(paths)

    expect(store.count).to eq(0)
  end
end
