# frozen_string_literal: true

module DevIntel
  module Database
    # The index schema, as an ordered list of [version, SQL].
    #
    # Append new versions; never edit one that has shipped, because an index
    # built by an earlier DevIntel has already applied it. Migrations live
    # apart from the Migrator that runs them so that this file can grow with
    # the schema without the runner growing with it.
    module Migrations
      ALL = [
        [
          1,
          <<~SQL
            CREATE TABLE files (
              id         INTEGER PRIMARY KEY AUTOINCREMENT,
              path       TEXT    NOT NULL UNIQUE,
              language   TEXT    NOT NULL,
              hash       TEXT    NOT NULL,
              size       INTEGER NOT NULL,
              updated_at TEXT    NOT NULL
            );

            CREATE INDEX index_files_on_language ON files (language);

            CREATE TABLE metadata (
              key   TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
          SQL
        ],
        [
          2,
          <<~SQL
            CREATE TABLE symbols (
              id             INTEGER PRIMARY KEY AUTOINCREMENT,
              file_id        INTEGER NOT NULL REFERENCES files (id) ON DELETE CASCADE,
              type           TEXT    NOT NULL,
              name           TEXT    NOT NULL,
              qualified_name TEXT    NOT NULL,
              line_start     INTEGER NOT NULL,
              line_end       INTEGER NOT NULL
            );

            CREATE INDEX index_symbols_on_file_id ON symbols (file_id);
            CREATE INDEX index_symbols_on_qualified_name ON symbols (qualified_name);
            CREATE INDEX index_symbols_on_name ON symbols (name);

            -- Named `symbol_references` because REFERENCES is a reserved word
            -- in SQLite and would need quoting in every statement.
            CREATE TABLE symbol_references (
              id               INTEGER PRIMARY KEY AUTOINCREMENT,
              file_id          INTEGER NOT NULL REFERENCES files (id) ON DELETE CASCADE,
              source_symbol_id INTEGER REFERENCES symbols (id) ON DELETE CASCADE,
              type             TEXT    NOT NULL,
              target_name      TEXT,
              resolution       TEXT    NOT NULL,
              line             INTEGER NOT NULL
            );

            CREATE INDEX index_symbol_references_on_file_id ON symbol_references (file_id);
            CREATE INDEX index_symbol_references_on_target_name ON symbol_references (target_name);

            -- 'ok' or 'error': a file whose syntax Prism rejects contributes no
            -- symbols, and that gap has to stay visible rather than look empty.
            ALTER TABLE files ADD COLUMN parse_state TEXT NOT NULL DEFAULT 'ok';
          SQL
        ],
        [
          3,
          <<~SQL
            -- Calls and constant references need more than a target name: the
            -- lexical scope the reference was written in (Ruby resolves
            -- constants outwards from there) and how the receiver was written.
            ALTER TABLE symbol_references ADD COLUMN source_scope TEXT NOT NULL DEFAULT '';
            ALTER TABLE symbol_references ADD COLUMN receiver_kind TEXT;
            ALTER TABLE symbol_references ADD COLUMN receiver_name TEXT;

            -- Filled in by Graph::Resolver once every file has been indexed.
            -- The qualified name is what queries match on, because a class
            -- reopened in two files has two symbol rows but one name; the id
            -- is kept as a precise anchor to one of those definitions.
            ALTER TABLE symbol_references ADD COLUMN target_symbol_id INTEGER;
            ALTER TABLE symbol_references ADD COLUMN target_qualified_name TEXT;

            -- `FileStore.new` calls a method this repository never defines, but
            -- the receiver is one of its classes. Recording the resolved
            -- receiver keeps that dependency visible instead of discarding it
            -- because `new` happens to come from Class.
            ALTER TABLE symbol_references ADD COLUMN receiver_qualified_name TEXT;

            CREATE INDEX index_symbol_references_on_target_qualified_name
              ON symbol_references (target_qualified_name);
            CREATE INDEX index_symbol_references_on_receiver_qualified_name
              ON symbol_references (receiver_qualified_name);
            CREATE INDEX index_symbol_references_on_source_symbol_id
              ON symbol_references (source_symbol_id);
            CREATE INDEX index_symbol_references_on_resolution
              ON symbol_references (resolution);
          SQL
        ]
      ].freeze

      LATEST_VERSION = ALL.map(&:first).max
    end
  end
end
