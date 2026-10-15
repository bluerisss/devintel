# frozen_string_literal: true

RSpec.describe DevIntel::Database::ReferenceStore do
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

  let(:symbol_ids) do
    DevIntel::Database::SymbolStore.new(@connection).insert_all(
      @file_id,
      [DevIntel::Parser::ExtractedSymbol.new(
        type: "class", name: "A", qualified_name: "A", line_start: 1, line_end: 3
      )]
    )
  end

  def reference(type: "INHERITS", source_index: 0, target_name: "Base",
                source_scope: "A", receiver_kind: nil, receiver_name: nil, line: 1)
    DevIntel::Parser::ExtractedReference.new(
      type: type, source_index: source_index, source_scope: source_scope,
      receiver_kind: receiver_kind, receiver_name: receiver_name,
      target_name: target_name, line: line
    )
  end

  it "links a reference to the symbol its source_index points at" do
    store.insert_all(@file_id, [reference], symbol_ids)

    expect(store.for_file(@file_id).first.source_symbol_id).to eq(symbol_ids.first)
  end

  it "stores a reference with no source symbol for top-level code" do
    store.insert_all(@file_id, [reference(source_index: nil)], symbol_ids)

    expect(store.for_file(@file_id).first.source_symbol_id).to be_nil
  end

  it "stores edges unresolved, for Graph::Resolver to decide afterwards" do
    store.insert_all(@file_id, [reference], symbol_ids)

    expect(store.for_file(@file_id).first.resolution).to eq(DevIntel::Graph::Resolution::PENDING)
  end

  it "keeps the lexical scope and receiver a call was written with" do
    store.insert_all(
      @file_id,
      [reference(type: "CALLS", source_scope: "Billing::Invoice",
                 receiver_kind: "constant", receiver_name: "PaymentService", target_name: "charge")],
      symbol_ids
    )

    record = store.for_file(@file_id).first
    expect(record.source_scope).to eq("Billing::Invoice")
    expect(record.receiver_kind).to eq("constant")
    expect(record.receiver_name).to eq("PaymentService")
    expect(record.target_name).to eq("charge")
  end

  it "counts edges by resolution" do
    store.insert_all(@file_id, [reference, reference], symbol_ids)

    expect(store.count_by_resolution).to eq(DevIntel::Graph::Resolution::PENDING => 2)
  end

  it "removes a file's references on replace" do
    store.insert_all(@file_id, [reference], symbol_ids)

    store.delete_for_file(@file_id)

    expect(store.count).to eq(0)
  end

  it "removes references when the owning symbol is deleted" do
    store.insert_all(@file_id, [reference], symbol_ids)

    DevIntel::Database::SymbolStore.new(@connection).delete_for_file(@file_id)

    expect(store.count).to eq(0)
  end
end
