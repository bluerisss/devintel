# frozen_string_literal: true

require "devintel/version"
require "devintel/errors"
require "devintel/workspace"
require "devintel/repository/detector"
require "devintel/repository/git"
require "devintel/diff/hunk_parser"
require "devintel/diff/analyzer"
require "devintel/parser/extracted"
require "devintel/parser/constants"
require "devintel/parser/scope"
require "devintel/parser/call_sites"
require "devintel/parser/method_naming"
require "devintel/parser/symbol_extractor"
require "devintel/parser/ruby_parser"
require "devintel/graph/resolution"
require "devintel/graph/constant_lookup"
require "devintel/graph/resolver"
require "devintel/graph/symbol_graph"
require "devintel/graph/trace"
require "devintel/index/language"
require "devintel/index/source_file"
require "devintel/index/content_digest"
require "devintel/index/file_discovery"
require "devintel/index/file_analyzer"
require "devintel/index/totals"
require "devintel/index/indexer"
require "devintel/database/connection"
require "devintel/database/migrations"
require "devintel/database/migrator"
require "devintel/database/file_store"
require "devintel/database/symbol_store"
require "devintel/database/reference_store"
require "devintel/database/metadata_store"
require "devintel/presenters/index_summary"
require "devintel/presenters/table"
require "devintel/presenters/diff"
require "devintel/presenters/trace"
require "devintel/ui/api"
require "devintel/ui/server"

# DevIntel is a local-first code intelligence engine.
#
# It analyses the target repository *statically*: it never requires, boots or
# connects to the application under analysis, so DevIntel's Ruby version is
# independent of the target project's Ruby version.
module DevIntel
end
