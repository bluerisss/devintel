# frozen_string_literal: true

require "net/http"
require "json"
require "stringio"

# Starts a real DevIntel::UI::Server and talks to it over real HTTP.
#
# The server is exercised end to end rather than through its handler methods
# because the bugs that matter here live in the boundary itself: WEBrick's
# parameter decoding, Host checking and status codes are invisible to a test
# that calls Ruby methods directly.
module RunningServer
  # Port 0 asks the OS for a free one, so parallel runs cannot collide.
  def with_server(root)
    workspace = DevIntel::Workspace.new(root)
    server = DevIntel::UI::Server.new(workspace, port: free_port, output: StringIO.new)
    thread = Thread.new { server.start }
    wait_until_listening(server)

    yield Client.new(server.url)
  ensure
    thread&.kill
  end

  def free_port
    socket = TCPServer.new("127.0.0.1", 0)
    port = socket.addr[1]
    socket.close
    port
  end

  def wait_until_listening(server, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      TCPSocket.new("127.0.0.1", URI(server.url).port).close
      return
    rescue Errno::ECONNREFUSED
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "server did not start within #{timeout}s"
      end

      sleep 0.02
    end
  end

  # A deliberately tiny HTTP client: enough to assert status, headers and body.
  class Client
    Response = Data.define(:status, :headers, :body) do
      def json
        JSON.parse(body)
      end
    end

    def initialize(base_url)
      @base = URI(base_url)
    end

    def get(path, headers: {})
      uri = URI.join(@base, path)
      response = Net::HTTP.start(uri.host, uri.port) { |http| http.get(uri.request_uri, headers) }

      Response.new(status: response.code.to_i, headers: response, body: response.body)
    end
  end
end
