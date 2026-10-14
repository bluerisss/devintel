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
        expect(stdout).to include("Ruby files:\n  1")
        expect(stdout).to include("Indexed:\n  1")
        expect(root.join(".devintel/index.sqlite")).to exist
      end
    end

    it "finds the repository root from a nested working directory" do
      with_repository("app/models/user.rb" => "class User; end\n") do |root|
        stdout, _stderr, status = run("index", chdir: root.join("app/models"))

        expect(status).to eq(0)
        expect(stdout).to include("Repository:\n  #{root}")
        expect(root.join(".devintel/index.sqlite")).to exist
      end
    end

    it "reports no work on a second run" do
      with_repository("a.rb" => "A = 1\n") do |root|
        run("index", chdir: root)

        stdout, _stderr, status = run("index", chdir: root)

        expect(status).to eq(0)
        expect(stdout).to include("Changed:\n  0")
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
end
