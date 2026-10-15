# frozen_string_literal: true

require "thor"
require "devintel"

module DevIntel
  # Command-line entry point.
  #
  # The CLI parses arguments, calls one application service and prints the
  # result. It holds no analysis logic: every command here should read as
  # "build input -> call service -> present output".
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    map %w[--version -v] => :version

    desc "version", "Print the DevIntel version"
    def version
      say "devintel #{DevIntel::VERSION}"
    end

    desc "index", "Build or update the local code index for this repository"
    method_option :path, type: :string, default: ".",
                         desc: "Directory inside the repository to start from"
    method_option :force, type: :boolean, default: false,
                          desc: "Re-index every file, ignoring unchanged content hashes"
    def index
      workspace = Workspace.discover(options[:path])
      result = Index::Indexer.new(workspace).call(force: options[:force])
      say Presenters::IndexSummary.new(result).to_s
    rescue DevIntel::Error => e
      abort_with(e)
    end

    desc "trace SYMBOL", "Show what reaches a symbol, what it reaches, and which tests name it"
    method_option :path, type: :string, default: ".",
                         desc: "Directory inside the repository to start from"
    def trace(symbol)
      workspace = Workspace.discover(options[:path])
      result = Graph::Trace.call(workspace, symbol)
      say Presenters::Trace.new(result).to_s
    rescue DevIntel::Error => e
      abort_with(e)
    end

    private

    # Expected failures are a readable message on stderr and exit 1; anything
    # else is a bug and keeps its backtrace.
    def abort_with(error)
      warn "devintel: #{error.message}"
      exit 1
    end
  end
end
