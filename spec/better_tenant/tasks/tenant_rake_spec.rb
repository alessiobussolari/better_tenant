# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "better_tenant rake tasks" do
  let(:mock_connection) { double("connection") }

  before do
    # Load rake tasks
    Rails.application.load_tasks unless Rake::Task.task_defined?("better_tenant:list")

    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }
  end

  after do
    BetterTenant::Tenant.reset!
  end

  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def configure_column_strategy
    BetterTenant.configure do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[acme globex initech]
      c.require_tenant false
    end
  end

  def configure_schema_strategy
    BetterTenant.configure do |c|
      c.strategy :schema
      c.tenant_names %w[acme globex initech]
      c.persistent_schemas %w[shared]
      c.schema_format "tenant_%{tenant}"
      c.require_tenant false
    end
  end

  describe "better_tenant:list" do
    it "lists all configured tenants" do
      configure_column_strategy
      allow(BetterTenant::Tenant).to receive(:exists?).and_return(true)

      output = capture_output do
        Rake::Task["better_tenant:list"].reenable
        Rake::Task["better_tenant:list"].invoke
      end

      expect(output).to include("Configured tenants:")
      expect(output).to include("acme")
      expect(output).to include("globex")
      expect(output).to include("initech")
    end

    it "shows checkmark for existing tenants" do
      configure_column_strategy
      allow(BetterTenant::Tenant).to receive(:exists?).with("acme").and_return(true)
      allow(BetterTenant::Tenant).to receive(:exists?).with("globex").and_return(false)
      allow(BetterTenant::Tenant).to receive(:exists?).with("initech").and_return(true)

      output = capture_output do
        Rake::Task["better_tenant:list"].reenable
        Rake::Task["better_tenant:list"].invoke
      end

      expect(output).to include("✓ acme")
      expect(output).to include("✗ globex")
      expect(output).to include("✓ initech")
    end

    it "aborts if not configured" do
      BetterTenant::Tenant.reset!

      expect {
        Rake::Task["better_tenant:list"].reenable
        Rake::Task["better_tenant:list"].invoke
      }.to raise_error(SystemExit)
    end
  end

  describe "better_tenant:config" do
    context "with column strategy" do
      before { configure_column_strategy }

      it "displays strategy" do
        output = capture_output do
          Rake::Task["better_tenant:config"].reenable
          Rake::Task["better_tenant:config"].invoke
        end

        expect(output).to include("Strategy: column")
      end

      it "displays tenant column" do
        output = capture_output do
          Rake::Task["better_tenant:config"].reenable
          Rake::Task["better_tenant:config"].invoke
        end

        expect(output).to include("Tenant column: tenant_id")
      end

      it "displays require_tenant setting" do
        output = capture_output do
          Rake::Task["better_tenant:config"].reenable
          Rake::Task["better_tenant:config"].invoke
        end

        expect(output).to include("Require tenant: false")
      end
    end

    context "with schema strategy" do
      before { configure_schema_strategy }

      it "displays schema strategy" do
        output = capture_output do
          Rake::Task["better_tenant:config"].reenable
          Rake::Task["better_tenant:config"].invoke
        end

        expect(output).to include("Strategy: schema")
      end

      it "displays schema format" do
        output = capture_output do
          Rake::Task["better_tenant:config"].reenable
          Rake::Task["better_tenant:config"].invoke
        end

        expect(output).to include("Schema format: tenant_%{tenant}")
      end

      it "displays persistent schemas" do
        output = capture_output do
          Rake::Task["better_tenant:config"].reenable
          Rake::Task["better_tenant:config"].invoke
        end

        expect(output).to include("Persistent schemas: shared")
      end
    end

    it "displays excluded models when present" do
      BetterTenant.configure do |c|
        c.strategy :column
        c.tenant_column :tenant_id
        c.tenant_names %w[acme]
        c.excluded_models %w[User Tenant]
      end

      output = capture_output do
        Rake::Task["better_tenant:config"].reenable
        Rake::Task["better_tenant:config"].invoke
      end

      expect(output).to include("Excluded models: User, Tenant")
    end
  end

  describe "better_tenant:create" do
    context "with schema strategy" do
      before { configure_schema_strategy }

      it "creates a tenant" do
        allow(BetterTenant::Tenant).to receive(:create)

        output = capture_output do
          Rake::Task["better_tenant:create"].reenable
          Rake::Task["better_tenant:create"].invoke("new_tenant")
        end

        expect(output).to include("Creating tenant: new_tenant")
        expect(output).to include("Tenant 'new_tenant' created successfully!")
        expect(BetterTenant::Tenant).to have_received(:create).with("new_tenant")
      end

      it "aborts without tenant name" do
        expect {
          Rake::Task["better_tenant:create"].reenable
          Rake::Task["better_tenant:create"].invoke
        }.to raise_error(SystemExit)
      end

      it "handles creation errors" do
        allow(BetterTenant::Tenant).to receive(:create).and_raise(
          BetterTenant::Errors::TenantNotFoundError.new(tenant_name: "existing_tenant")
        )

        expect {
          Rake::Task["better_tenant:create"].reenable
          Rake::Task["better_tenant:create"].invoke("existing_tenant")
        }.to raise_error(SystemExit)
      end
    end

    context "with column strategy" do
      before { configure_column_strategy }

      it "aborts for column strategy" do
        expect {
          Rake::Task["better_tenant:create"].reenable
          Rake::Task["better_tenant:create"].invoke("tenant")
        }.to raise_error(SystemExit)
      end
    end
  end

  describe "better_tenant:drop" do
    context "with schema strategy" do
      before { configure_schema_strategy }

      it "drops a tenant after confirmation" do
        allow(BetterTenant::Tenant).to receive(:drop)
        allow($stdin).to receive(:gets).and_return("yes\n")

        output = capture_output do
          Rake::Task["better_tenant:drop"].reenable
          Rake::Task["better_tenant:drop"].invoke("old_tenant")
        end

        expect(output).to include("WARNING: This will permanently delete all data")
        expect(output).to include("Tenant 'old_tenant' dropped successfully!")
        expect(BetterTenant::Tenant).to have_received(:drop).with("old_tenant")
      end

      it "cancels on no confirmation" do
        allow(BetterTenant::Tenant).to receive(:drop)
        allow($stdin).to receive(:gets).and_return("no\n")

        output = capture_output do
          Rake::Task["better_tenant:drop"].reenable
          Rake::Task["better_tenant:drop"].invoke("old_tenant")
        end

        expect(output).to include("Operation cancelled.")
        expect(BetterTenant::Tenant).not_to have_received(:drop)
      end

      it "aborts without tenant name" do
        expect {
          Rake::Task["better_tenant:drop"].reenable
          Rake::Task["better_tenant:drop"].invoke
        }.to raise_error(SystemExit)
      end
    end

    context "with column strategy" do
      before { configure_column_strategy }

      it "aborts for column strategy" do
        expect {
          Rake::Task["better_tenant:drop"].reenable
          Rake::Task["better_tenant:drop"].invoke("tenant")
        }.to raise_error(SystemExit)
      end
    end
  end

  describe "better_tenant:migrate" do
    context "with schema strategy" do
      before { configure_schema_strategy }

      it "runs migrations for all tenants" do
        # Create a real-looking db:migrate task double
        db_migrate_task = double("db:migrate task", reenable: nil, invoke: nil)
        allow(Rake::Task).to receive(:[]).and_call_original
        allow(Rake::Task).to receive(:[]).with("db:migrate").and_return(db_migrate_task)

        allow(BetterTenant::Tenant).to receive(:each).and_yield("acme").and_yield("globex")

        output = capture_output do
          Rake::Task["better_tenant:migrate"].reenable
          Rake::Task["better_tenant:migrate"].invoke
        end

        expect(output).to include("Running migrations for all tenants")
        expect(output).to include("Migrating tenant: acme")
        expect(output).to include("Migrating tenant: globex")
        expect(output).to include("All tenant migrations completed!")
      end
    end

    context "with column strategy" do
      before { configure_column_strategy }

      it "aborts for column strategy" do
        expect {
          Rake::Task["better_tenant:migrate"].reenable
          Rake::Task["better_tenant:migrate"].invoke
        }.to raise_error(SystemExit)
      end
    end
  end

  describe "better_tenant:rollback" do
    context "with schema strategy" do
      before { configure_schema_strategy }

      it "rolls back migrations for all tenants" do
        db_rollback_task = double("db:rollback task", reenable: nil, invoke: nil)
        allow(Rake::Task).to receive(:[]).and_call_original
        allow(Rake::Task).to receive(:[]).with("db:rollback").and_return(db_rollback_task)

        allow(BetterTenant::Tenant).to receive(:each).and_yield("acme").and_yield("globex")

        output = capture_output do
          Rake::Task["better_tenant:rollback"].reenable
          Rake::Task["better_tenant:rollback"].invoke
        end

        expect(output).to include("Rolling back migrations for all tenants")
        expect(output).to include("Rolling back tenant: acme")
        expect(output).to include("Rolling back tenant: globex")
        expect(output).to include("All tenant rollbacks completed!")
      end
    end

    context "with column strategy" do
      before { configure_column_strategy }

      it "aborts for column strategy" do
        expect {
          Rake::Task["better_tenant:rollback"].reenable
          Rake::Task["better_tenant:rollback"].invoke
        }.to raise_error(SystemExit)
      end
    end
  end

  describe "better_tenant:seed" do
    it "seeds all tenants" do
      configure_column_strategy

      db_seed_task = double("db:seed task", reenable: nil, invoke: nil)
      allow(Rake::Task).to receive(:[]).and_call_original
      allow(Rake::Task).to receive(:[]).with("db:seed").and_return(db_seed_task)

      allow(BetterTenant::Tenant).to receive(:each).and_yield("acme").and_yield("globex")

      output = capture_output do
        Rake::Task["better_tenant:seed"].reenable
        Rake::Task["better_tenant:seed"].invoke
      end

      expect(output).to include("Seeding all tenants")
      expect(output).to include("Seeding tenant: acme")
      expect(output).to include("Seeding tenant: globex")
      expect(output).to include("All tenants seeded!")
    end
  end

  describe "better_tenant:console" do
    before { configure_column_strategy }

    it "switches to tenant before console" do
      switched_tenant = nil
      allow(BetterTenant::Tenant).to receive(:switch!) { |tenant| switched_tenant = tenant }

      # Mock IRB to avoid actually starting console
      allow_any_instance_of(Object).to receive(:require).with("irb").and_return(true)
      irb_mock = double("IRB")
      stub_const("IRB", irb_mock)
      allow(irb_mock).to receive(:start)

      output = capture_output do
        Rake::Task["better_tenant:console"].reenable
        Rake::Task["better_tenant:console"].invoke("acme")
      end

      expect(output).to include("Switched to tenant: acme")
      expect(switched_tenant).to eq("acme")
    end

    it "aborts without tenant name" do
      expect {
        Rake::Task["better_tenant:console"].reenable
        Rake::Task["better_tenant:console"].invoke
      }.to raise_error(SystemExit)
    end
  end

  describe "better_tenant:each" do
    before { configure_column_strategy }

    it "executes task for each tenant" do
      custom_task = double("custom task", reenable: nil, invoke: nil)
      allow(Rake::Task).to receive(:[]).and_call_original
      allow(Rake::Task).to receive(:[]).with("custom:task").and_return(custom_task)

      allow(BetterTenant::Tenant).to receive(:each).and_yield("acme").and_yield("globex")

      output = capture_output do
        Rake::Task["better_tenant:each"].reenable
        Rake::Task["better_tenant:each"].invoke("custom:task")
      end

      expect(output).to include("Running 'custom:task' for all tenants")
      expect(output).to include("Tenant: acme")
      expect(output).to include("Tenant: globex")
      expect(output).to include("Task completed for all tenants!")
    end

    it "aborts without task name" do
      expect {
        Rake::Task["better_tenant:each"].reenable
        Rake::Task["better_tenant:each"].invoke
      }.to raise_error(SystemExit)
    end
  end

  describe "helper methods" do
    describe "require_tenant_configuration!" do
      it "aborts with helpful message when not configured" do
        BetterTenant::Tenant.reset!

        expect {
          Rake::Task["better_tenant:list"].reenable
          Rake::Task["better_tenant:list"].invoke
        }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    describe "require_schema_strategy!" do
      it "aborts with helpful message for column strategy" do
        configure_column_strategy

        expect {
          Rake::Task["better_tenant:create"].reenable
          Rake::Task["better_tenant:create"].invoke("tenant")
        }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "allows schema strategy tasks" do
        configure_schema_strategy
        allow(BetterTenant::Tenant).to receive(:create)

        expect {
          capture_output do
            Rake::Task["better_tenant:create"].reenable
            Rake::Task["better_tenant:create"].invoke("tenant")
          end
        }.not_to raise_error
      end
    end
  end
end
