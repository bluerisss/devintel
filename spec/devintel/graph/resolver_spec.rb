# frozen_string_literal: true

# The resolver is asserted through a real index: it exists to connect symbols
# across files, which is exactly what a unit test with stubs would not prove.
RSpec.describe DevIntel::Graph::Resolver do
  def index(files, &block)
    with_repository(files) do |root|
      DevIntel::Index::Indexer.new(DevIntel::Workspace.new(root)).call
      DevIntel::Database::Connection.open(DevIntel::Workspace.new(root).database_path, &block)
    end
  end

  def edges(connection)
    connection.execute(<<~SQL)
      SELECT r.type, r.resolution, r.target_name, r.target_qualified_name, r.receiver_qualified_name,
             src.qualified_name AS source
      FROM symbol_references r
      LEFT JOIN symbols src ON src.id = r.source_symbol_id
      ORDER BY r.id
    SQL
  end

  def edge(connection, type:, target_name: nil)
    edges(connection).find do |row|
      row["type"] == type && (target_name.nil? || row["target_name"] == target_name)
    end
  end

  describe "constants" do
    it "resolves a superclass defined in another file" do
      index("a.rb" => "class Base; end\n", "b.rb" => "class Child < Base; end\n") do |connection|
        found = edge(connection, type: "INHERITS")

        expect(found["resolution"]).to eq("resolved")
        expect(found["target_qualified_name"]).to eq("Base")
      end
    end

    it "resolves a mixin through the enclosing namespace" do
      files = {
        "a.rb" => "module Billing\n  module Payable; end\nend\n",
        "b.rb" => "module Billing\n  class Invoice\n    include Payable\n  end\nend\n"
      }

      index(files) do |connection|
        expect(edge(connection, type: "INCLUDES")["target_qualified_name"]).to eq("Billing::Payable")
      end
    end

    it "marks a constant this repository does not define as named, not resolved" do
      index("a.rb" => "class Child < ActiveRecord::Base; end\n") do |connection|
        found = edge(connection, type: "INHERITS")

        expect(found["resolution"]).to eq("named")
        expect(found["target_qualified_name"]).to be_nil
      end
    end

    it "marks a superclass that names nothing as dynamic" do
      index("a.rb" => "class Child < Struct.new(:a); end\n") do |connection|
        expect(edge(connection, type: "INHERITS")["resolution"]).to eq("dynamic")
      end
    end
  end

  describe "calls" do
    it "resolves a singleton call on a constant" do
      files = {
        "a.rb" => "class PaymentService\n  def self.charge(x); end\nend\n",
        "b.rb" => "class Checkout\n  def run; PaymentService.charge(1); end\nend\n"
      }

      index(files) do |connection|
        found = edge(connection, type: "CALLS", target_name: "charge")

        expect(found["resolution"]).to eq("resolved")
        expect(found["target_qualified_name"]).to eq("PaymentService.charge")
        expect(found["source"]).to eq("Checkout#run")
      end
    end

    it "infers the receiver of a call on Foo.new, and labels it as inferred" do
      files = {
        "a.rb" => "class PaymentService\n  def charge(x); end\nend\n",
        "b.rb" => "class Checkout\n  def run; PaymentService.new.charge(1); end\nend\n"
      }

      index(files) do |connection|
        found = edge(connection, type: "CALLS", target_name: "charge")

        expect(found["resolution"]).to eq("inferred")
        expect(found["target_qualified_name"]).to eq("PaymentService#charge")
      end
    end

    it "keeps the receiver when the class is ours but the method is not defined here" do
      files = {
        "a.rb" => "class PaymentService; end\n",
        "b.rb" => "class Checkout\n  def run; PaymentService.new; end\nend\n"
      }

      index(files) do |connection|
        found = edge(connection, type: "CALLS", target_name: "new")

        expect(found["resolution"]).to eq("receiver_only")
        expect(found["receiver_qualified_name"]).to eq("PaymentService")
        expect(found["target_qualified_name"]).to be_nil
      end
    end

    it "marks a call on an unknown receiver as such" do
      index("a.rb" => "class A\n  def run(order); order.total; end\nend\n") do |connection|
        expect(edge(connection, type: "CALLS", target_name: "total")["resolution"]).to eq("unknown_receiver")
      end
    end

    it "resolves a call to a sibling method on self" do
      source = "class A\n  def run; notify; end\n  def notify; end\nend\n"

      index("a.rb" => source) do |connection|
        found = edge(connection, type: "CALLS", target_name: "notify")

        expect(found["resolution"]).to eq("resolved")
        expect(found["target_qualified_name"]).to eq("A#notify")
      end
    end

    it "resolves a self call inside a singleton method against the class" do
      source = "class A\n  def self.run; helper; end\n  def self.helper; end\nend\n"

      index("a.rb" => source) do |connection|
        expect(edge(connection, type: "CALLS",
                                target_name: "helper")["target_qualified_name"]).to eq("A.helper")
      end
    end

    it "drops a receiverless call it cannot attribute instead of inventing an edge" do
      index("a.rb" => "class A\n  def run; puts 'x'; end\nend\n") do |connection|
        expect(edge(connection, type: "CALLS", target_name: "puts")).to be_nil
      end
    end

    it "reports how many receiverless calls it dropped" do
      with_repository("a.rb" => "class A\n  def run; puts 'x'; raise 'y'; end\nend\n") do |root|
        result = DevIntel::Index::Indexer.new(DevIntel::Workspace.new(root)).call

        expect(result.unattributed_self_calls).to eq(2)
      end
    end
  end

  it "re-resolves edges when a later run adds the file that defines the target" do
    with_repository("b.rb" => "class Child < Base; end\n") do |root|
      workspace = DevIntel::Workspace.new(root)
      DevIntel::Index::Indexer.new(workspace).call

      resolution = DevIntel::Database::Connection.open(workspace.database_path) do |connection|
        edge(connection, type: "INHERITS")["resolution"]
      end
      expect(resolution).to eq("named")

      write_file(root, "a.rb", "class Base; end\n")
      DevIntel::Index::Indexer.new(workspace).call

      DevIntel::Database::Connection.open(workspace.database_path) do |connection|
        expect(edge(connection, type: "INHERITS")["resolution"]).to eq("resolved")
      end
    end
  end
end
