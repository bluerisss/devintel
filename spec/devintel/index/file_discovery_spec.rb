# frozen_string_literal: true

RSpec.describe DevIntel::Index::FileDiscovery do
  def discover(root)
    described_class.new(root).call
  end

  it "finds Ruby source files at any depth" do
    with_repository(
      "app/services/user_service.rb" => "",
      "app/models/user.rb" => "",
      "spec/services/user_service_spec.rb" => ""
    ) do |root|
      expect(discover(root).map(&:path)).to eq(
        [
          "app/models/user.rb",
          "app/services/user_service.rb",
          "spec/services/user_service_spec.rb"
        ]
      )
    end
  end

  it "recognises Ruby files that have no .rb extension" do
    with_repository(
      "Rakefile" => "", "Gemfile" => "", "config.ru" => "",
      "devintel.gemspec" => "", "lib/tasks/import.rake" => ""
    ) do |root|
      expect(discover(root).map(&:path)).to contain_exactly(
        "Gemfile", "Rakefile", "config.ru", "devintel.gemspec", "lib/tasks/import.rake"
      )
    end
  end

  it "recognises extensionless executables by their Ruby shebang" do
    with_repository(
      "bin/console" => "#!/usr/bin/env ruby\nIRB.start\n",
      "bin/setup" => "#!/bin/bash\nbundle install\n",
      "bin/deploy" => "#!/usr/bin/env python3\nprint(1)\n"
    ) do |root|
      expect(discover(root).map(&:path)).to eq(["bin/console"])
    end
  end

  it "does not sniff files that already have a non-Ruby extension" do
    with_repository("script.sh" => "#!/usr/bin/env ruby\n") do |root|
      expect(discover(root).map(&:path)).to be_empty
    end
  end

  it "treats an empty or unreadable extensionless file as not Ruby" do
    with_repository("CHANGELOG" => "", "NOTICE" => "no shebang here\n") do |root|
      expect(discover(root).map(&:path)).to be_empty
    end
  end

  it "skips non-Ruby files" do
    with_repository(
      "app/models/user.rb" => "",
      "README.md" => "", "app/assets/app.js" => "", "config/database.yml" => ""
    ) do |root|
      expect(discover(root).map(&:path)).to eq(["app/models/user.rb"])
    end
  end

  it "ignores vendored, generated and DevIntel-owned directories" do
    with_repository(
      "app/models/user.rb" => "",
      ".git/hooks/pre-commit.rb" => "",
      ".devintel/scratch.rb" => "",
      "node_modules/pkg/index.rb" => "",
      "tmp/cache/thing.rb" => "",
      "log/replay.rb" => "",
      "vendor/bundle/gem.rb" => ""
    ) do |root|
      expect(discover(root).map(&:path)).to eq(["app/models/user.rb"])
    end
  end

  it "ignores those directories at any depth, not only at the root" do
    with_repository(
      "app/models/user.rb" => "",
      "engines/billing/node_modules/pkg/index.rb" => "",
      "engines/billing/tmp/cache.rb" => ""
    ) do |root|
      expect(discover(root).map(&:path)).to eq(["app/models/user.rb"])
    end
  end

  it "accepts an explicit ignore list" do
    with_repository("app/models/user.rb" => "", "spec/models/user_spec.rb" => "") do |root|
      paths = described_class.new(root, ignored_directories: %w[spec]).call.map(&:path)

      expect(paths).to eq(["app/models/user.rb"])
    end
  end

  it "does not follow symlinks, which could escape the repository or loop" do
    with_repository("app/models/user.rb" => "") do |root|
      File.symlink(root.join("app"), root.join("app_link"))
      File.symlink(root.join("app/models/user.rb"), root.join("alias.rb"))

      expect(discover(root).map(&:path)).to eq(["app/models/user.rb"])
    end
  end

  it "tags discovered files with their language and absolute path" do
    with_repository("app/models/user.rb" => "class User; end\n") do |root|
      file = discover(root).first

      expect(file.language).to eq("ruby")
      expect(file.absolute_path).to eq(root.join("app/models/user.rb"))
    end
  end

  it "returns files in a deterministic order" do
    with_repository("b.rb" => "", "a.rb" => "", "lib/c.rb" => "") do |root|
      expect(discover(root).map(&:path)).to eq(["a.rb", "b.rb", "lib/c.rb"])
    end
  end
end
