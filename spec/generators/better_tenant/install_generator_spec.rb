# frozen_string_literal: true

require "rails_helper"
require "generators/better_tenant/install_generator"

RSpec.describe BetterTenant::Generators::InstallGenerator, type: :generator do
  let(:destination_root) { File.expand_path("../../../tmp/generator_test", __dir__) }

  before do
    FileUtils.mkdir_p(destination_root)
    FileUtils.mkdir_p(File.join(destination_root, "config/initializers"))
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))

    # Create a minimal application.rb for injection test
    File.write(
      File.join(destination_root, "config/application.rb"),
      <<~RUBY
        module TestApp
          class Application < Rails::Application
          end
        end
      RUBY
    )

    allow(Rails).to receive(:root).and_return(Pathname.new(destination_root))

    # Stub timestamped_migrations for Rails 7+ compatibility
    # Use singleton class to define the method if it doesn't exist
    unless ActiveRecord::Base.respond_to?(:timestamped_migrations)
      ActiveRecord::Base.define_singleton_method(:timestamped_migrations) { true }
    end
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  def run_generator(args = [])
    described_class.start(args, destination_root: destination_root)
  end

  def file_content(path)
    File.read(File.join(destination_root, path))
  end

  def file_exists?(path)
    File.exist?(File.join(destination_root, path))
  end

  describe "initializer generation" do
    it "creates initializer file" do
      run_generator
      expect(file_exists?("config/initializers/better_tenant.rb")).to be true
    end

    it "includes BetterTenant.configure block" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("BetterTenant.configure do |config|")
    end

    it "includes strategy configuration" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.strategy")
    end

    it "includes tenant_names configuration" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.tenant_names")
    end

    it "includes excluded_models configuration" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.excluded_models")
    end
  end

  describe "with --strategy=column option (default)" do
    it "creates initializer with column strategy" do
      run_generator(["--strategy=column"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.strategy :column")
    end

    it "includes tenant_column configuration" do
      run_generator(["--strategy=column"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.tenant_column :tenant_id")
    end

    it "does not include schema-specific options" do
      run_generator(["--strategy=column"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).not_to include("config.persistent_schemas")
      expect(content).not_to include("config.schema_format")
    end
  end

  describe "with --strategy=schema option" do
    it "creates initializer with schema strategy" do
      run_generator(["--strategy=schema"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.strategy :schema")
    end

    it "includes persistent_schemas configuration" do
      run_generator(["--strategy=schema"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.persistent_schemas")
    end

    it "includes schema_format configuration" do
      run_generator(["--strategy=schema"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.schema_format")
    end

    it "does not include tenant_column" do
      run_generator(["--strategy=schema"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).not_to include("config.tenant_column :tenant_id")
    end
  end

  describe "with --migration flag" do
    # Note: Migration generation tests require more complex setup
    # The generator uses Rails internal migration_template which requires
    # specific Rails environment configuration

    context "without table specified" do
      it "does not create migration" do
        run_generator(["--strategy=column", "--migration"])
        migration_files = Dir.glob(File.join(destination_root, "db/migrate/*.rb"))
        expect(migration_files).to be_empty
      end
    end

    context "with schema strategy" do
      it "does not create migration even with table" do
        # Schema strategy should not create migration for tenant_id
        run_generator(["--strategy=schema", "--table=articles"])
        migration_files = Dir.glob(File.join(destination_root, "db/migrate/*.rb"))
        expect(migration_files).to be_empty
      end
    end
  end

  describe "with custom --tenant_column" do
    it "uses custom column name in initializer" do
      run_generator(["--strategy=column", "--tenant_column=organization_id"])
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.tenant_column :organization_id")
    end
  end

  describe "middleware config injection" do
    it "injects middleware comments into application.rb" do
      run_generator
      content = file_content("config/application.rb")
      expect(content).to include("BetterTenant::Middleware")
    end

    it "includes subdomain elevator option" do
      run_generator
      content = file_content("config/application.rb")
      expect(content).to include(":subdomain")
    end

    it "includes header elevator option" do
      run_generator
      content = file_content("config/application.rb")
      expect(content).to include(":header")
    end

    it "includes path elevator option" do
      run_generator
      content = file_content("config/application.rb")
      expect(content).to include(":path")
    end
  end

  describe "idempotent runs" do
    it "does not duplicate initializer content on second run" do
      run_generator
      content_before = file_content("config/initializers/better_tenant.rb")
      run_generator
      content_after = file_content("config/initializers/better_tenant.rb")
      expect(content_after).to eq(content_before)
    end
  end

  describe "common configurations" do
    it "includes require_tenant option" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.require_tenant")
    end

    it "includes strict_mode option" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.strict_mode")
    end

    it "includes excluded_subdomains option" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.excluded_subdomains")
    end

    it "includes excluded_paths option" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("config.excluded_paths")
    end

    it "includes callback examples" do
      run_generator
      content = file_content("config/initializers/better_tenant.rb")
      expect(content).to include("before_create")
      expect(content).to include("after_create")
      expect(content).to include("before_switch")
      expect(content).to include("after_switch")
    end
  end
end
