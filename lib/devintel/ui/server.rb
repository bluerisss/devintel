# frozen_string_literal: true

require "webrick"
require "json"

module DevIntel
  module UI
    # Serves the knowledge map on the loopback interface.
    #
    # Local-first is a security property here, not just a deployment choice:
    # the server exposes the structure of the developer's source code, so it
    # binds to 127.0.0.1 and rejects requests whose Host header says they came
    # from anywhere else. That second check matters because any page in the
    # browser can issue requests to localhost; without it, a visited website
    # could read the shape of a private codebase.
    class Server
      DEFAULT_PORT = 7421
      BIND_ADDRESS = "127.0.0.1"

      ALLOWED_HOSTS = ["localhost", "127.0.0.1", "[::1]", "::1"].freeze

      INVALID_ENCODING = { error: "Query parameters must be valid UTF-8." }.freeze

      # An explicit map rather than joining a path from the request: a file can
      # only be served if it is listed here, so path traversal has nothing to
      # traverse.
      ASSETS = {
        "/" => ["index.html", "text/html; charset=utf-8"],
        "/app.css" => ["app.css", "text/css; charset=utf-8"],
        "/app.js" => ["app.js", "text/javascript; charset=utf-8"]
      }.freeze

      PUBLIC_DIR = File.expand_path("public", __dir__)

      def initialize(workspace, port: DEFAULT_PORT, output: $stdout)
        @workspace = workspace
        @port = port
        @output = output
        @api = Api.new(workspace)
      end

      def start
        ensure_index!
        server = build_server
        trap_signals(server)

        @output.puts(banner)
        # The banner is the only sign the server came up; without a flush it
        # sits in the buffer until shutdown whenever stdout is redirected.
        @output.flush
        server.start
      end

      # @return [String] the address the UI is reachable at.
      def url
        "http://#{BIND_ADDRESS}:#{@port}"
      end

      private

      def ensure_index!
        return if @workspace.database_path.exist?

        raise IndexNotFoundError, "No index at #{@workspace.database_path}. Run `devintel index` first."
      end

      def build_server
        server = WEBrick::HTTPServer.new(
          BindAddress: BIND_ADDRESS, Port: @port,
          Logger: WEBrick::Log.new(File::NULL), AccessLog: []
        )
        mount(server)
        server
      rescue Errno::EADDRINUSE
        raise Error, "Port #{@port} is already in use. Start the map on another port with --port."
      end

      def mount(server)
        server.mount_proc("/") { |request, response| handle(request, response) }
      end

      def handle(request, response)
        return forbid(response) unless local_host?(request)

        route(request, response)
      rescue DevIntel::Error => e
        write_json(response, 500, { error: e.message })
      end

      def route(request, response)
        case request.path
        when "/api/stats" then write_json(response, 200, @api.stats)
        when "/api/search" then search(request, response)
        when "/api/symbol" then symbol(request, response)
        else asset(request, response)
        end
      end

      def search(request, response)
        query = param(request, "q")
        return write_json(response, 400, INVALID_ENCODING) if query.nil?

        write_json(response, 200, @api.search(query, limit: request.query["limit"] || Api::DEFAULT_SEARCH_LIMIT))
      end

      def symbol(request, response)
        name = param(request, "name")
        return write_json(response, 400, INVALID_ENCODING) if name.nil?
        return write_json(response, 400, { error: "name is required" }) if name.empty?

        result = @api.symbol(name)
        return write_json(response, result.status, result.body) if result.is_a?(Api::Failure)

        write_json(response, 200, result)
      end

      # WEBrick hands query parameters back as ASCII-8BIT. Ruby compares such a
      # string equal to its UTF-8 twin, so the difference is invisible in
      # application code — but the sqlite3 driver binds a binary string as a
      # BLOB, and `WHERE name = ?` against a TEXT column then matches nothing.
      # Every lookup would quietly report "no such symbol". Decoding here keeps
      # that out of every query below.
      #
      # @return [String, nil] nil when the bytes are not valid UTF-8.
      def param(request, key)
        value = request.query[key].to_s.dup.force_encoding(Encoding::UTF_8)

        value.valid_encoding? ? value : nil
      end

      def asset(request, response)
        file, content_type = ASSETS[request.path]
        return write_json(response, 404, { error: "Not found" }) if file.nil?

        response.status = 200
        response["Content-Type"] = content_type
        # The index is rebuilt by `devintel index`, so a cached page would show
        # a stale codebase after re-indexing.
        response["Cache-Control"] = "no-store"
        response.body = File.read(File.join(PUBLIC_DIR, file))
      end

      # Strips the port: "localhost:7421" and "localhost" are the same origin.
      def local_host?(request)
        host = request.header["host"]&.first.to_s.sub(/:\d+\z/, "")

        ALLOWED_HOSTS.include?(host)
      end

      def forbid(response)
        write_json(response, 403, { error: "DevIntel only answers requests addressed to localhost." })
      end

      def write_json(response, status, body)
        response.status = status
        response["Content-Type"] = "application/json; charset=utf-8"
        response["Cache-Control"] = "no-store"
        response.body = JSON.generate(body)
      end

      def trap_signals(server)
        %w[INT TERM].each { |signal| Signal.trap(signal) { server.shutdown } }
      end

      def banner
        <<~TEXT
          DevIntel Knowledge Map

            Repository  #{@workspace.root}
            Serving     #{url}

          Local only; nothing leaves this machine. Press Ctrl-C to stop.
        TEXT
      end
    end
  end
end
