# frozen_string_literal: true

require_relative "lib/devintel/version"

Gem::Specification.new do |spec|
  spec.name        = "devintel"
  spec.version     = DevIntel::VERSION
  spec.authors     = ["Sabitech"]
  spec.summary     = "Local-first developer intelligence for Ruby codebases."
  spec.description = <<~DESC.strip
    DevIntel is a standalone CLI that builds a local, deterministic index of a Ruby
    codebase: files, symbols, references and their relationships. It analyses source
    statically and never loads the target application.
  DESC
  spec.homepage = "https://github.com/sabitech/devintel"
  spec.license  = "MIT"

  # DevIntel runs on its own Ruby, independent of the target application's Ruby.
  # 3.3 is the floor because Prism ships as a default gem from 3.3 onwards.
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob("lib/**/*.rb") + Dir.glob("lib/**/public/*") + Dir.glob("bin/*") +
               %w[README.md LICENSE devintel.gemspec]
  spec.bindir      = "bin"
  spec.executables = ["devintel"]
  spec.require_paths = ["lib"]

  # Prism is the official Ruby parser: error tolerant, precise about locations,
  # and decoupled from the running Ruby, so DevIntel can read syntax from a
  # Ruby version other than its own. It ships as a default gem from Ruby 3.3,
  # but is declared explicitly so the version in use is pinned rather than
  # whatever the host Ruby happens to bundle.
  spec.add_dependency "prism", "~> 1.0"   # Ruby AST
  spec.add_dependency "sqlite3", "~> 2.0" # local index storage
  spec.add_dependency "thor", "~> 1.3"    # CLI parsing / subcommands
  # Serving the local UI. Not in the standard library since Ruby 3.0, and the
  # alternative is hand-written HTTP on TCPServer: request parsing, response
  # framing and concurrency that DevIntel would then own and have to get right.
  spec.add_dependency "webrick", "~> 1.8" # local HTTP server for `devintel map`

  spec.metadata["rubygems_mfa_required"] = "true"
end
