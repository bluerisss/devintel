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

  spec.files = Dir.glob("lib/**/*.rb") + Dir.glob("bin/*") + %w[README.md LICENSE devintel.gemspec]
  spec.bindir      = "bin"
  spec.executables = ["devintel"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sqlite3", "~> 2.0" # local index storage
  spec.add_dependency "thor", "~> 1.3"    # CLI parsing / subcommands

  spec.metadata["rubygems_mfa_required"] = "true"
end
