# frozen_string_literal: true

RSpec.describe DevIntel::Database::Migrator do
  def with_connection(&block)
    with_directory do |root|
      DevIntel::Database::Connection.open(root.join("index.sqlite"), &block)
    end
  end

  it "creates the schema and records the applied version" do
    with_connection do |connection|
      described_class.new(connection).migrate!

      tables = connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'").map { |r| r["name"] }
      expect(tables).to include("files", "metadata", "schema_migrations")
      expect(described_class.new(connection).current_version).to eq(described_class::LATEST_VERSION)
    end
  end

  it "is idempotent and does not destroy existing rows" do
    with_connection do |connection|
      described_class.new(connection).migrate!
      DevIntel::Database::FileStore.new(connection)
                                   .insert(path: "a.rb", language: "ruby", hash: "abc", size: 1)

      described_class.new(connection).migrate!

      expect(DevIntel::Database::FileStore.new(connection).count).to eq(1)
    end
  end

  it "refuses an index written by a newer DevIntel instead of corrupting it" do
    with_connection do |connection|
      described_class.new(connection).migrate!
      connection.execute("INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)", [999, "now"])

      expect { described_class.new(connection).migrate! }
        .to raise_error(DevIntel::SchemaTooNewError, /newer DevIntel/)
    end
  end

  it "enforces one row per path" do
    with_connection do |connection|
      described_class.new(connection).migrate!
      store = DevIntel::Database::FileStore.new(connection)
      store.insert(path: "a.rb", language: "ruby", hash: "abc", size: 1)

      expect { store.insert(path: "a.rb", language: "ruby", hash: "def", size: 2) }
        .to raise_error(SQLite3::ConstraintException)
    end
  end
end
