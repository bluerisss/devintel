# frozen_string_literal: true

RSpec.describe DevIntel::Parser::SymbolExtractor do
  def extract(source)
    DevIntel::Parser::RubyParser.parse(source)
  end

  def definitions(source)
    extract(source).symbols.map { |symbol| [symbol.type, symbol.qualified_name] }
  end

  STRUCTURAL = %w[INHERITS INCLUDES EXTENDS PREPENDS].freeze

  # Inheritance and mixins. Calls and constant references are asserted
  # separately so these examples stay about the structure of the code.
  def relationships(source)
    extract(source).references
                   .select { |reference| STRUCTURAL.include?(reference.type) }
                   .map { |reference| [reference.type, reference.target_name, resolution_of(reference)] }
  end

  def resolution_of(reference)
    reference.dynamic? ? "dynamic" : "named"
  end

  def calls(source)
    extract(source).references
                   .select { |reference| reference.type == "CALLS" }
                   .map do |reference|
      [reference.receiver_kind, reference.receiver_name,
       reference.target_name]
    end
  end

  def constant_references(source)
    extract(source).references
                   .select { |reference| reference.type == "REFERENCES" }
                   .map(&:target_name)
  end

  describe "classes and modules" do
    it "extracts a class" do
      expect(definitions("class User; end")).to eq([%w[class User]])
    end

    it "extracts a module" do
      expect(definitions("module Billing; end")).to eq([%w[module Billing]])
    end

    it "qualifies a nested definition by its enclosing namespace" do
      expect(definitions("module Billing\n  class Invoice; end\nend")).to eq(
        [["module", "Billing"], ["class", "Billing::Invoice"]]
      )
    end

    it "keeps a compact path as written" do
      expect(definitions("class Billing::Invoice; end")).to eq([["class", "Billing::Invoice"]])
    end

    it "records a reopened class twice rather than collapsing it" do
      expect(definitions("class User; end\nclass User; end")).to eq(
        [%w[class User], %w[class User]]
      )
    end

    it "records the simple name alongside the qualified name" do
      symbol = extract("module Billing\n  class Invoice; end\nend").symbols.last

      expect(symbol.name).to eq("Invoice")
      expect(symbol.qualified_name).to eq("Billing::Invoice")
    end
  end

  describe "methods" do
    it "marks an instance method with #" do
      expect(definitions("class User\n  def name; end\nend")).to include(["method", "User#name"])
    end

    it "marks a `def self.` method with ." do
      expect(definitions("class User\n  def self.find; end\nend")).to include(
        ["singleton_method", "User.find"]
      )
    end

    it "treats methods inside `class << self` as singleton methods" do
      source = "class User\n  class << self\n    def build; end\n  end\nend"

      expect(definitions(source)).to include(["singleton_method", "User.build"])
    end

    it "returns to instance methods after the singleton block closes" do
      source = "class User\n  class << self\n    def build; end\n  end\n  def name; end\nend"

      expect(definitions(source)).to include(["singleton_method", "User.build"], ["method", "User#name"])
    end

    it "attributes `def Foo.bar` to the constant it names" do
      expect(definitions("def Foo.bar; end")).to eq([["singleton_method", "Foo.bar"]])
    end

    it "keeps a non-constant receiver verbatim instead of attributing it to the enclosing scope" do
      expect(definitions("class User\n  def obj.bar; end\nend")).to include(
        ["singleton_method", "obj.bar"]
      )
    end

    it "leaves a top-level method unqualified" do
      expect(definitions("def helper; end")).to eq([%w[method helper]])
    end

    it "extracts methods nested inside another method body" do
      expect(definitions("class A\n  def outer\n    def inner; end\n  end\nend")).to include(
        ["method", "A#outer"], ["method", "A#inner"]
      )
    end
  end

  describe "constants" do
    it "qualifies a constant by its enclosing namespace" do
      expect(definitions("class User\n  ROLES = []\nend")).to include(["constant", "User::ROLES"])
    end

    it "extracts a top-level constant" do
      expect(definitions("VERSION = '1.0'")).to eq([%w[constant VERSION]])
    end

    it "extracts a constant written through a path" do
      symbol = extract("Billing::LIMIT = 5").symbols.first

      expect(symbol.type).to eq("constant")
      expect(symbol.qualified_name).to eq("Billing::LIMIT")
      expect(symbol.name).to eq("LIMIT")
    end

    it "extracts a class assigned to a constant" do
      expect(definitions("Wrapper = Class.new")).to eq([%w[constant Wrapper]])
    end
  end

  describe "line numbers" do
    it "spans a multi-line class from its keyword to its end" do
      symbol = extract("# comment\nclass User\n  def a; end\nend\n").symbols.first

      expect([symbol.line_start, symbol.line_end]).to eq([2, 4])
    end

    it "spans a multi-line method" do
      symbol = extract("class User\n  def name\n    @name\n  end\nend").symbols.last

      expect([symbol.line_start, symbol.line_end]).to eq([2, 4])
    end
  end

  describe "inheritance" do
    it "records a named superclass" do
      expect(relationships("class User < ApplicationRecord; end")).to eq(
        [%w[INHERITS ApplicationRecord named]]
      )
    end

    it "records a namespaced superclass as written" do
      expect(relationships("class User < Billing::Base; end")).to eq(
        [["INHERITS", "Billing::Base", "named"]]
      )
    end

    it "keeps a root-scoped superclass distinguishable" do
      expect(relationships("class User < ::Base; end")).to eq([["INHERITS", "::Base", "named"]])
    end

    it "records a computed superclass as dynamic instead of guessing" do
      expect(relationships("class Wrapper < Struct.new(:a); end")).to eq(
        [["INHERITS", nil, "dynamic"]]
      )
    end

    it "treats a constant path with a computed part as dynamic" do
      expect(relationships("class User < config::Base; end")).to eq([["INHERITS", nil, "dynamic"]])
    end

    it "records no relationship when there is no superclass" do
      expect(relationships("class User; end")).to be_empty
    end

    it "points the relationship at the class that declares it" do
      result = extract("class A; end\nclass B < Base; end")
      reference = result.references.first

      expect(result.symbols[reference.source_index].qualified_name).to eq("B")
    end

    it "records the line of the superclass" do
      expect(extract("\n\nclass User < Base; end").references.first.line).to eq(3)
    end
  end

  describe "mixins" do
    it "records include, extend and prepend as distinct edge types" do
      source = "class User\n  include Payable\n  extend Findable\n  prepend Audited\nend"

      expect(relationships(source)).to eq(
        [%w[INCLUDES Payable named],
         %w[EXTENDS Findable named],
         %w[PREPENDS Audited named]]
      )
    end

    it "records one edge per argument" do
      expect(relationships("class User\n  include A, B\nend")).to eq(
        [%w[INCLUDES A named], %w[INCLUDES B named]]
      )
    end

    it "records a computed module as dynamic instead of guessing" do
      expect(relationships("class User\n  include build_module\nend")).to eq(
        [["INCLUDES", nil, "dynamic"]]
      )
    end

    it "attributes the mixin to the class that declares it" do
      result = extract("class A\n  include X\nend")

      expect(result.symbols[result.references.first.source_index].qualified_name).to eq("A")
    end

    it "leaves a top-level mixin without a source symbol" do
      expect(extract("include Kernel").references.first.source_index).to be_nil
    end

    it "ignores an RSpec include matcher, which is also a receiverless call named include" do
      expect(relationships('it("x") { expect(out).to include("y") }')).to be_empty
    end

    it "ignores a matcher even inside a class body" do
      expect(relationships('class A\n  def check; expect(x).to include(Y); end\nend')).to be_empty
    end

    it "still records a mixin guarded by a condition" do
      expect(relationships("class A\n  include B if legacy?\nend")).to eq(
        [%w[INCLUDES B named]]
      )
    end

    it "still records a mixin inside a block, as ActiveSupport::Concern writes it" do
      expect(relationships("module M\n  included do\n    include B\n  end\nend")).to eq(
        [%w[INCLUDES B named]]
      )
    end

    it "ignores a call named include that has a receiver" do
      expect(relationships("class A\n  list.include(x)\nend")).to be_empty
    end

    it "ignores include? which is a different method" do
      expect(relationships("class A\n  def a; list.include?(x); end\nend")).to be_empty
    end
  end

  describe "method calls" do
    it "records a call on a constant with the constant as receiver" do
      expect(calls("class A\n  def run; PaymentService.charge(1); end\nend")).to eq(
        [%w[constant PaymentService charge]]
      )
    end

    it "treats the result of Foo.new as an instance of Foo" do
      source = "class A\n  def run; PaymentService.new.charge(1); end\nend"

      expect(calls(source)).to include(%w[instance PaymentService charge])
    end

    it "still records the constructor call itself" do
      source = "class A\n  def run; PaymentService.new.charge(1); end\nend"

      expect(calls(source)).to include(%w[constant PaymentService new])
    end

    it "records a receiverless call as a call on self" do
      expect(calls("class A\n  def run; notify; end\nend")).to eq([["self", nil, "notify"]])
    end

    it "treats an explicit self receiver the same way" do
      expect(calls("class A\n  def run; self.notify; end\nend")).to eq([["self", nil, "notify"]])
    end

    it "admits that it does not know the type of an arbitrary receiver" do
      expect(calls("class A\n  def run(order); order.total; end\nend")).to eq(
        [["unknown", nil, "total"]]
      )
    end

    it "attributes a call to the method that makes it, not to the class" do
      result = extract("class A\n  def run; B.go; end\nend")
      call = result.references.find { |reference| reference.type == "CALLS" }

      expect(result.symbols[call.source_index].qualified_name).to eq("A#run")
    end

    it "records the lexical scope so constants can be resolved later" do
      result = extract("module M\n  class A\n    def run; B.go; end\n  end\nend")
      call = result.references.find { |reference| reference.type == "CALLS" }

      expect(call.source_scope).to eq("M::A")
    end

    it "ignores operators, which are calls but carry no relationship" do
      expect(calls("class A\n  def run(x); x + 1 == 2; end\nend")).to be_empty
    end

    it "ignores attribute assignment" do
      expect(calls("class A\n  def run(x); x.name = 1; end\nend")).to be_empty
    end

    it "ignores calls on literals" do
      expect(calls("class A\n  def run; 'text'.upcase; [].map; end\nend")).to be_empty
    end

    it "records the method named by a literal send, which is determinable" do
      expect(calls("class A\n  def run(x); x.send(:charge); end\nend")).to eq(
        [["unknown", nil, "charge"]]
      )
    end

    it "records a computed send as dynamic rather than dropping it" do
      reference = extract("class A\n  def run(x, m); x.send(m); end\nend")
                  .references.find { |r| r.type == "CALLS" && r.target_name.nil? }

      expect(reference).not_to be_nil
      expect(reference).to be_dynamic
    end
  end

  describe "constant references" do
    it "records a constant used as a value" do
      expect(constant_references("class A\n  def run; MAX_RETRIES; end\nend")).to eq(["MAX_RETRIES"])
    end

    it "records a namespaced constant as written" do
      expect(constant_references("class A\n  def run; Billing::LIMIT; end\nend")).to eq(["Billing::LIMIT"])
    end

    it "does not record a constant receiver twice, once as call and once as reference" do
      expect(constant_references("class A\n  def run; PaymentService.charge; end\nend")).to be_empty
    end

    it "does not record a superclass twice" do
      expect(constant_references("class A < Base; end")).to be_empty
    end

    it "does not record a mixin argument twice" do
      expect(constant_references("class A\n  include Payable\nend")).to be_empty
    end

    it "records a constant passed as an argument, which is how specs name a class" do
      expect(constant_references("RSpec.describe UserService do; end")).to eq(["UserService"])
    end
  end

  describe "Ruby dynamism" do
    it "does not invent a method for define_method" do
      expect(definitions("class User\n  define_method(:dynamic) { 1 }\nend")).to eq([%w[class User]])
    end

    it "does not invent a method for send" do
      expect(definitions("class User\n  send(:attr_accessor, :name)\nend")).to eq([%w[class User]])
    end

    it "does not invent symbols for eval" do
      expect(definitions("class User\n  class_eval('def x; end')\nend")).to eq([%w[class User]])
    end

    it "does not invent methods for Rails-style macros" do
      expect(definitions("class User < ApplicationRecord\n  belongs_to :account\nend")).to eq(
        [%w[class User]]
      )
    end
  end
end
