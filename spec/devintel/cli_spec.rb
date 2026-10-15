# frozen_string_literal: true

require "devintel/cli"
require "open3"

# End-to-end coverage of the shipped executable: these run `bin/devintel` as a
# user would, so they also prove the gem loads without Bundler's help.
RSpec.describe "devintel executable" do
  EXECUTABLE = File.expand_path("../../bin/devintel", __dir__)

  def run(*args, chdir: Dir.pwd)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, EXECUTABLE, *args, chdir: chdir.to_s)
    [stdout, stderr, status.exitstatus]
  end

  describe "--version" do
    it "prints the version" do
      stdout, _stderr, status = run("--version")

      expect(stdout.strip).to eq("devintel #{DevIntel::VERSION}")
      expect(status).to eq(0)
    end

    it "accepts the version subcommand and -v alias" do
      expect(run("version").first.strip).to eq("devintel #{DevIntel::VERSION}")
      expect(run("-v").first.strip).to eq("devintel #{DevIntel::VERSION}")
    end
  end

  describe "index" do
    it "indexes the repository it is run inside and prints a summary" do
      with_repository("app/models/user.rb" => "class User; end\n", "README.md" => "docs") do |root|
        stdout, _stderr, status = run("index", chdir: root)

        expect(status).to eq(0)
        expect(stdout).to match(/1\s+Ruby file\s+found on disk/)
        expect(stdout).to match(/1\s+parsed/)
        expect(stdout).to match(/1\s+symbol\s/)
        expect(root.join(".devintel/index.sqlite")).to exist
      end
    end

    it "finds the repository root from a nested working directory" do
      with_repository("app/models/user.rb" => "class User; end\n") do |root|
        stdout, _stderr, status = run("index", chdir: root.join("app/models"))

        expect(status).to eq(0)
        expect(stdout).to include("Repository  #{root}")
        expect(root.join(".devintel/index.sqlite")).to exist
      end
    end

    it "reports the symbols and relationships it extracted" do
      source = "class User < ApplicationRecord\n  include Trackable\n  def name; end\nend\n"
      with_repository("app/models/user.rb" => source) do |root|
        stdout, _stderr, status = run("index", chdir: root)

        expect(status).to eq(0)
        expect(stdout).to match(/2\s+symbols\s+class 1, method 1/)
        expect(stdout).to match(/2\s+relationships\s+INCLUDES 1, INHERITS 1/)
        expect(stdout).to match(/0\s+unparsed files/)
      end
    end

    it "reports no work on a second run" do
      with_repository("a.rb" => "A = 1\n") do |root|
        run("index", chdir: root)

        stdout, _stderr, status = run("index", chdir: root)

        expect(status).to eq(0)
        expect(stdout).to match(/0\s+parsed/)
        expect(stdout).to match(/1\s+skipped\s+unchanged since the last run/)
      end
    end

    it "fails with a readable message outside a Git repository" do
      with_directory do |dir|
        stdout, stderr, status = run("index", chdir: dir)

        expect(status).to eq(1)
        expect(stderr).to include("not inside a Git repository")
        expect(stdout).to be_empty
      end
    end
  end

  describe "trace" do
    let(:files) do
      {
        "app/services/payment_service.rb" => "class PaymentService\n  def charge(x); end\nend\n",
        "app/services/order_service.rb" =>
          "class OrderService\n  def execute(o)\n    PaymentService.new.charge(1)\n  end\nend\n",
        "spec/services/order_service_spec.rb" => "RSpec.describe OrderService do; end\n"
      }
    end

    it "shows definition, callers, callees and tests" do
      with_repository(files) do |root|
        run("index", chdir: root)

        stdout, _stderr, status = run("trace", "OrderService", chdir: root)

        expect(status).to eq(0)
        expect(stdout).to start_with("OrderService\n")
        expect(stdout).to match(%r{class\s+app/services/order_service\.rb:1-5})
        expect(stdout).to match(/PaymentService#charge\s+CALLS\s+INFERENCE/)
        expect(stdout).to include("spec/services/order_service_spec.rb")
      end
    end

    it "accepts a simple name" do
      with_repository("a.rb" => "module Billing\n  class Invoice; end\nend\n") do |root|
        run("index", chdir: root)

        stdout, _stderr, status = run("trace", "Invoice", chdir: root)

        expect(status).to eq(0)
        expect(stdout).to start_with("Billing::Invoice\n")
      end
    end

    it "tells the developer to index first instead of failing obscurely" do
      with_repository("a.rb" => "class A; end\n") do |root|
        _stdout, stderr, status = run("trace", "A", chdir: root)

        expect(status).to eq(1)
        expect(stderr).to include("Run `devintel index` first")
      end
    end

    it "reports an unknown symbol as a message, not a crash" do
      with_repository("a.rb" => "class A; end\n") do |root|
        run("index", chdir: root)

        _stdout, stderr, status = run("trace", "Missing", chdir: root)

        expect(status).to eq(1)
        expect(stderr).to include("No symbol named Missing")
      end
    end
  end
end
