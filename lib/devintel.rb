# frozen_string_literal: true

require "devintel/version"
require "devintel/errors"
require "devintel/workspace"
require "devintel/repository/detector"
require "devintel/index/source_file"
require "devintel/index/content_digest"
require "devintel/index/file_discovery"
require "devintel/index/indexer"
require "devintel/database/connection"
require "devintel/database/migrator"
require "devintel/database/file_store"
require "devintel/database/metadata_store"

# DevIntel is a local-first code intelligence engine.
#
# It analyses the target repository *statically*: it never requires, boots or
# connects to the application under analysis, so DevIntel's Ruby version is
# independent of the target project's Ruby version.
module DevIntel
end
