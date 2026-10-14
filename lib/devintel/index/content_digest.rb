# frozen_string_literal: true

require "digest"

module DevIntel
  module Index
    # Content hash used to decide whether a file must be re-analysed.
    #
    # Content-based rather than mtime-based: mtime changes on checkout, rebase
    # and `touch` without the content changing, which would make re-indexing do
    # pointless work. SHA-256 is read streaming, so large files do not have to
    # be held in memory.
    module ContentDigest
      ALGORITHM = "sha256"

      def self.call(absolute_path)
        Digest::SHA256.file(absolute_path.to_s).hexdigest
      end
    end
  end
end
