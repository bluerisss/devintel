# frozen_string_literal: true

RSpec.describe DevIntel::UI::Server do
  let(:files) do
    {
      "app/services/payment_service.rb" => "class PaymentService\n  def charge(x); end\nend\n",
      "app/services/order_service.rb" =>
        "class OrderService\n  def execute(o)\n    PaymentService.new.charge(1)\n  end\nend\n",
      "spec/services/order_service_spec.rb" => "RSpec.describe OrderService do; end\n"
    }
  end

  def with_indexed_server(repo_files = files, &block)
    with_repository(repo_files) do |root|
      DevIntel::Index::Indexer.new(DevIntel::Workspace.new(root)).call
      with_server(root, &block)
    end
  end

  describe "GET /" do
    it "serves the page" do
      with_indexed_server do |client|
        response = client.get("/")

        expect(response.status).to eq(200)
        expect(response.headers["content-type"]).to include("text/html")
        expect(response.body).to include("DevIntel Knowledge Map")
      end
    end

    it "serves the stylesheet and script" do
      with_indexed_server do |client|
        expect(client.get("/app.css").status).to eq(200)
        expect(client.get("/app.js").status).to eq(200)
      end
    end

    it "does not let a cached page outlive a re-index" do
      with_indexed_server do |client|
        expect(client.get("/").headers["cache-control"]).to eq("no-store")
      end
    end

    it "serves only the files it lists, so there is no path to traverse" do
      with_indexed_server do |client|
        expect(client.get("/../../../etc/passwd").status).to eq(404)
        expect(client.get("/app.rb").status).to eq(404)
      end
    end
  end

  describe "GET /api/stats" do
    it "reports what the index holds" do
      with_indexed_server do |client|
        body = client.get("/api/stats").json

        expect(body["files"]).to eq(3)
        expect(body["symbols"]).to be > 0
        expect(body["relationships"]).to be > 0
      end
    end
  end

  describe "GET /api/search" do
    it "finds symbols by substring" do
      with_indexed_server do |client|
        names = client.get("/api/search?q=Payment").json["results"].map { |r| r["qualified_name"] }

        expect(names).to include("PaymentService")
      end
    end

    it "returns an empty result rather than an error for a blank query" do
      with_indexed_server do |client|
        response = client.get("/api/search?q=")

        expect(response.status).to eq(200)
        expect(response.json["results"]).to be_empty
      end
    end
  end

  describe "GET /api/symbol" do
    # WEBrick decodes query parameters as ASCII-8BIT. Ruby compares such a
    # string equal to its UTF-8 twin, but sqlite3 binds it as a BLOB, so
    # `WHERE name = ?` against a TEXT column silently matches nothing. The bug
    # is invisible to a test that calls the API in Ruby, so this one goes over
    # HTTP on purpose.
    it "finds a symbol by name given over the wire" do
      with_indexed_server do |client|
        response = client.get("/api/symbol?name=OrderService")

        expect(response.status).to eq(200)
        expect(response.json["query"]).to eq("OrderService")
      end
    end

    it "finds a namespaced symbol whose name is percent-encoded" do
      with_repository("a.rb" => "module Billing\n  class Invoice; end\nend\n") do |root|
        DevIntel::Index::Indexer.new(DevIntel::Workspace.new(root)).call

        with_server(root) do |client|
          response = client.get("/api/symbol?name=#{ERB::Util.url_encode('Billing::Invoice')}")

          expect(response.json["query"]).to eq("Billing::Invoice")
        end
      end
    end

    it "returns callers, callees, tests and their evidence" do
      with_indexed_server do |client|
        body = client.get("/api/symbol?name=PaymentService").json

        # `PaymentService.new.charge(1)` is two relationships: constructing the
        # class is observed, calling #charge on the result is inferred.
        evidence = body["callers"]
                   .select { |relation| relation["qualified_name"] == "OrderService#execute" }
                   .map { |relation| relation["evidence"] }

        expect(evidence).to contain_exactly("FACT", "INFERENCE")
        expect(body["definitions"].first["path"]).to eq("app/services/payment_service.rb")
      end
    end

    it "links a spec to the symbol it names" do
      with_indexed_server do |client|
        body = client.get("/api/symbol?name=OrderService").json

        expect(body["tests"].map { |t| t["path"] }).to eq(["spec/services/order_service_spec.rb"])
      end
    end

    it "answers 404 for a symbol that is not indexed" do
      with_indexed_server do |client|
        response = client.get("/api/symbol?name=Missing")

        expect(response.status).to eq(404)
        expect(response.json["code"]).to eq("symbol_not_found")
      end
    end

    it "answers 409 for an ambiguous simple name instead of picking one" do
      ambiguous = {
        "a.rb" => "module Sales\n  class Invoice; end\nend\n",
        "b.rb" => "module Billing\n  class Invoice; end\nend\n"
      }

      with_indexed_server(ambiguous) do |client|
        response = client.get("/api/symbol?name=Invoice")

        expect(response.status).to eq(409)
        expect(response.json["code"]).to eq("ambiguous_symbol")
      end
    end

    it "requires a name" do
      with_indexed_server do |client|
        expect(client.get("/api/symbol?name=").status).to eq(400)
      end
    end
  end

  describe "keeping the codebase local" do
    # Any page in the browser can make requests to localhost. Without this
    # check, a visited website could read the structure of a private codebase.
    it "refuses a request addressed to another host" do
      with_indexed_server do |client|
        response = client.get("/api/stats", headers: { "Host" => "evil.example.com" })

        expect(response.status).to eq(403)
      end
    end

    it "accepts localhost and 127.0.0.1" do
      with_indexed_server do |client|
        expect(client.get("/api/stats", headers: { "Host" => "localhost:7421" }).status).to eq(200)
        expect(client.get("/api/stats", headers: { "Host" => "127.0.0.1" }).status).to eq(200)
      end
    end

    it "binds to the loopback interface only" do
      expect(described_class::BIND_ADDRESS).to eq("127.0.0.1")
    end
  end

  it "refuses to start without an index, pointing at the command that builds one" do
    with_repository("a.rb" => "class A; end\n") do |root|
      server = described_class.new(DevIntel::Workspace.new(root), port: free_port, output: StringIO.new)

      expect { server.start }.to raise_error(DevIntel::IndexNotFoundError, /devintel index/)
    end
  end
end
