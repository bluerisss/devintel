# frozen_string_literal: true

module DevIntel
  module Index
    # A source file that DevIntel considers part of the codebase.
    #
    # +path+ is always repository-relative and POSIX-separated.
    SourceFile = Data.define(:path, :language, :absolute_path)
  end
end
