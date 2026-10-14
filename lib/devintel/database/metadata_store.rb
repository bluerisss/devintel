# frozen_string_literal: true

module DevIntel
  module Database
    # Key/value facts about the index itself (schema provenance, last run).
    # Consumed by `devintel doctor` and by future commands that must refuse to
    # run against an index built by an incompatible DevIntel.
    class MetadataStore
      def initialize(connection)
        @connection = connection
      end

      def [](key)
        @connection.value("SELECT value FROM metadata WHERE key = ?", [key.to_s])
      end

      def []=(key, value)
        @connection.execute(
          "INSERT INTO metadata (key, value) VALUES (?, ?) " \
          "ON CONFLICT (key) DO UPDATE SET value = excluded.value",
          [key.to_s, value.to_s]
        )
      end

      def to_h
        @connection.execute("SELECT key, value FROM metadata").to_h { |row| [row["key"], row["value"]] }
      end
    end
  end
end
