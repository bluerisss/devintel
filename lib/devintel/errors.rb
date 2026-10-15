# frozen_string_literal: true

module DevIntel
  # Base class for every error DevIntel raises on purpose. The CLI turns these
  # into a readable message plus a non-zero exit status; anything else is a bug
  # and is allowed to surface with its backtrace.
  class Error < StandardError; end

  # The working directory is not inside a Git repository.
  class RepositoryNotFoundError < Error; end

  # The on-disk index is newer than this build of DevIntel understands.
  class SchemaTooNewError < Error; end

  # A command needs an index that has not been built yet.
  class IndexNotFoundError < Error; end

  # The name given to a command matches no symbol, or matches several.
  class SymbolNotFoundError < Error; end
  class AmbiguousSymbolError < Error; end
end
