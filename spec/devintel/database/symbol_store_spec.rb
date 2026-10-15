# frozen_string_literal: true

RSpec.describe DevIntel::Database::SymbolStore do
  around do |example|
    with_directory do |root|
      DevIntel::Database::Connection.open(root.join("index.sqlite")) do |connection|
        DevIntel::Database::Migrator.new(connection).migrate!
        @connection = connection
        @file_id = DevIntel::Database::FileStore.new(connection)
                                                .insert(path: "a.rb", language: "ruby", hash: "h", size: 1)
        example.run
      end
    end
  end

  subject(:store) { described_class.new(@connection) }

  def symbol(qualified_name, type: "class", line: 1)
    DevIntel::Parser::ExtractedSymbol.new(
      type: type, name: qualified_name.split("::").last,
      qualified_name: qualified_name, line_start: line, line_end: line
    )
  end

  it "stores symbols and returns their ids in insertion order" do
    ids = store.insert_all(@file_id, [symbol("A"), symbol("B")])

    expect(ids.size).to eq(2)
    expect(store.for_file(@file_id).map(&:qualified_name)).to eq(%w[A B])
    expect(store.for_file(@file_id).map(&:id)).to eq(ids)
  end

  it "replaces a file's symbols without touching other files" do
    other_file = DevIntel::Database::FileStore.new(@connection)
                                              .insert(path: "b.rb", language: "ruby", hash: "h", size: 1)
    store.insert_all(@file_id, [symbol("A")])
    store.insert_all(other_file, [symbol("B")])

    store.delete_for_file(@file_id)

    expect(store.for_file(@file_id)).to be_empty
    expect(store.for_file(other_file).map(&:qualified_name)).to eq(["B"])
  end

  it "removes a file's symbols when the file row is deleted" do
    store.insert_all(@file_id, [symbol("A")])

    DevIntel::Database::FileStore.new(@connection).delete_by_paths(["a.rb"])

    expect(store.count).to eq(0)
  end

  it "finds every definition sharing a qualified name, because Ruby reopens classes" do
    store.insert_all(@file_id, [symbol("A", line: 1), symbol("A", line: 10)])

    expect(store.find_by_qualified_name("A").map(&:line_start)).to eq([1, 10])
  end
end
