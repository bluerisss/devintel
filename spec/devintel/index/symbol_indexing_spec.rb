# frozen_string_literal: true

# End-to-end: a realistic little application on disk, indexed the way the CLI
# indexes it, asserted through the stored index rather than through the parser.
RSpec.describe "indexing a repository's symbols" do
  def index(root, force: false)
    DevIntel::Index::Indexer.new(DevIntel::Workspace.new(root)).call(force: force)
  end

  def with_index(root)
    DevIntel::Database::Connection.open(DevIntel::Workspace.new(root).database_path) do |connection|
      yield(
        DevIntel::Database::SymbolStore.new(connection),
        DevIntel::Database::ReferenceStore.new(connection),
        DevIntel::Database::FileStore.new(connection)
      )
    end
  end

  def qualified_names(root)
    with_index(root) do |symbols, _references, files|
      files.all_by_path.values.flat_map { |file| symbols.for_file(file.id) }.map(&:qualified_name)
    end
  end

  it "indexes the symbols of a realistic application" do
    with_fixture_repository("simple_app") do |root|
      index(root)

      expect(qualified_names(root)).to include(
        "User", "User::ROLES", "User#display_name", "User.active",
        "Services", "Services::UserService", "Services::UserService::DEFAULT_ROLE",
        "Services::UserService#execute", "Services::UserService.build"
      )
    end
  end

  it "indexes inheritance and mixins as distinct edge types" do
    with_fixture_repository("simple_app") do |root|
      index(root)

      edges = with_index(root) do |_symbols, references, files|
        files.all_by_path.values.flat_map { |file| references.for_file(file.id) }
             .map { |reference| [reference.type, reference.target_name] }
      end

      expect(edges).to include(
        %w[INHERITS ApplicationRecord], %w[INCLUDES Trackable],
        %w[INHERITS ApplicationService], %w[EXTENDS Forwardable], %w[PREPENDS Instrumented]
      )
    end
  end

  it "reports index-wide totals, not just this run's work" do
    with_fixture_repository("simple_app") do |root|
      first = index(root)
      second = index(root)

      expect(second.parsed).to eq(0)
      expect(second.symbols).to eq(first.symbols)
      expect(second.symbols).to be > 0
    end
  end

  it "replaces a changed file's symbols instead of accumulating them" do
    with_repository("a.rb" => "class A\n  def old; end\nend\n") do |root|
      index(root)
      write_file(root, "a.rb", "class A\n  def fresh; end\nend\n")

      index(root)

      expect(qualified_names(root)).to contain_exactly("A", "A#fresh")
    end
  end

  it "does not re-parse a file whose content is unchanged" do
    with_repository("a.rb" => "class A; end\n") do |root|
      index(root)

      parser = class_double(DevIntel::Parser::RubyParser).as_stubbed_const
      allow(parser).to receive(:parse_file).and_raise("should not be parsed again")

      expect { index(root) }.not_to raise_error
    end
  end

  it "removes symbols when their file is deleted" do
    with_repository("a.rb" => "class A; end\n", "b.rb" => "class B; end\n") do |root|
      index(root)
      root.join("b.rb").delete

      index(root)

      expect(qualified_names(root)).to eq(["A"])
    end
  end

  it "marks a file that does not parse and stores no symbols for it" do
    with_repository("good.rb" => "class Good; end\n", "bad.rb" => "class Bad\n  def oops(\nend\n") do |root|
      result = index(root)

      expect(result.parse_errors).to eq(1)
      expect(qualified_names(root)).to eq(["Good"])
      expect(with_index(root) { |_s, _r, files| files.all_by_path.keys }).to include("bad.rb")
    end
  end

  it "clears the error mark once the file parses again" do
    with_repository("bad.rb" => "class Bad\n  def oops(\nend\n") do |root|
      index(root)
      write_file(root, "bad.rb", "class Bad; end\n")

      expect(index(root).parse_errors).to eq(0)
    end
  end

  it "counts relationships by how far they could be resolved" do
    with_repository("a.rb" => "class A < Struct.new(:x)\n  include B\nend\n") do |root|
      result = index(root)

      # `Struct.new(:x)` names no superclass and `B` is defined nowhere here.
      expect(result.resolutions).to include(DevIntel::Graph::Resolution::DYNAMIC => 1)
      expect(result.traceable_references).to eq(0)
    end
  end

  it "re-analyses everything when a migration adds new capability to the index" do
    with_repository("a.rb" => "class A; end\n") do |root|
      workspace = DevIntel::Workspace.new(root)

      # A genuine schema-v1 index, built by applying only migration 1: the
      # file is hashed, but no symbol table exists yet.
      workspace.prepare!
      version, sql = DevIntel::Database::Migrations::ALL.first
      DevIntel::Database::Connection.open(workspace.database_path) do |connection|
        connection.execute(
          "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)"
        )
        connection.execute_batch(sql)
        connection.execute(
          "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)", [version,
                                                                                "2026-01-01T00:00:00Z"]
        )
        DevIntel::Database::FileStore.new(connection)
                                     .insert(path: "a.rb", language: "ruby",
                                             hash: Digest::SHA256.hexdigest("class A; end\n"), size: 13)
      end

      result = index(root)

      expect(result.modified).to eq(1)
      expect(qualified_names(root)).to eq(["A"])
    end
  end
end
