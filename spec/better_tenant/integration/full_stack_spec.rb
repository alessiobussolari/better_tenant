# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant Full Stack Integration" do
  # Full stack integration tests that test the complete flow from
  # middleware -> tenant switching -> model scoping -> response

  let(:mock_connection) { double("connection") }

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }

    BetterTenant.reset!
  end

  after do
    BetterTenant.reset!
  end

  describe "complete configuration and usage flow" do
    let(:tenant_model) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include BetterTenant::ActiveRecordExtension
      end
    end

    it "configures, switches tenants, and scopes queries correctly" do
      # Step 1: Configure BetterTenant
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme globex initech]
        config.require_tenant false
      end

      # Step 2: Verify initial state
      expect(BetterTenant::Tenant.current).to be_nil
      expect(BetterTenant::Tenant.tenant_names).to eq(%w[acme globex initech])

      # Step 3: Switch to tenant and verify scoping
      BetterTenant::Tenant.switch("acme") do
        expect(BetterTenant::Tenant.current).to eq("acme")

        # Queries should be scoped
        sql = tenant_model.all.to_sql
        expect(sql).to include("tenant_id")
        expect(sql).to include("acme")
      end

      # Step 4: After block, tenant should be reset
      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "middleware integration" do
    let(:app) { ->(env) { [200, {}, "OK"] } }
    let(:tenant_model) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include BetterTenant::ActiveRecordExtension
      end
    end

    it "integrates middleware with tenant switching" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme globex]
        config.require_tenant false
      end

      tenant_during_request = nil

      test_app = lambda do |env|
        tenant_during_request = BetterTenant::Tenant.current
        [200, {}, "OK"]
      end

      middleware = BetterTenant::Middleware.new(test_app, :header)
      env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "acme")

      # Execute request through middleware
      status, headers, body = middleware.call(env)

      expect(status).to eq(200)
      expect(tenant_during_request).to eq("acme")
      expect(BetterTenant::Tenant.current).to be_nil # Reset after request
    end
  end

  describe "callbacks integration" do
    it "triggers callbacks during tenant operations" do
      callback_log = []

      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme globex]
        config.require_tenant false

        config.before_switch do |from, to|
          callback_log << "before_switch: #{from} -> #{to}"
        end

        config.after_switch do |from, to|
          callback_log << "after_switch: #{from} -> #{to}"
        end
      end

      BetterTenant::Tenant.switch("acme") do
        # Inside tenant context
      end

      expect(callback_log).to include("before_switch:  -> acme")
      expect(callback_log).to include("after_switch:  -> acme")
    end
  end

  describe "error handling integration" do
    it "properly handles and propagates errors" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme]
        config.require_tenant true
      end

      # Unknown tenant should raise error
      expect {
        BetterTenant::Tenant.switch!("unknown")
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)

      # Still unconfigured after error
      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "model exclusion integration" do
    let(:excluded_model) do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include BetterTenant::ActiveRecordExtension
      end
      stub_const("ExcludedModel", klass)
      klass
    end

    let(:tenanted_model) do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include BetterTenant::ActiveRecordExtension
      end
      stub_const("TenantedModel", klass)
      klass
    end

    it "excludes specified models from tenant scoping" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme]
        config.excluded_models %w[ExcludedModel]
        config.require_tenant false
      end

      BetterTenant::Tenant.switch!("acme")

      # Excluded model should not have tenant scope
      expect(BetterTenant::Tenant.excluded_model?("ExcludedModel")).to be true
      expect(BetterTenant::Tenant.excluded_model?("TenantedModel")).to be false
    end
  end

  describe "tenant iteration integration" do
    it "iterates through all tenants with proper context" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme globex initech]
        config.require_tenant false
      end

      visited_tenants = []
      BetterTenant::Tenant.each do |tenant|
        expect(BetterTenant::Tenant.current).to eq(tenant)
        visited_tenants << tenant
      end

      expect(visited_tenants).to eq(%w[acme globex initech])
      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "dynamic tenant names integration" do
    it "supports dynamic tenant names via Proc" do
      dynamic_list = %w[tenant1 tenant2]

      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names -> { dynamic_list }
        config.require_tenant false
      end

      expect(BetterTenant::Tenant.tenant_names).to eq(%w[tenant1 tenant2])
      expect(BetterTenant::Tenant.exists?("tenant1")).to be true

      # Modify dynamic list
      dynamic_list << "tenant3"
      expect(BetterTenant::Tenant.tenant_names).to eq(%w[tenant1 tenant2 tenant3])
      expect(BetterTenant::Tenant.exists?("tenant3")).to be true
    end
  end

  describe "configuration access" do
    it "exposes configuration through various access points" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :org_id
        config.tenant_names %w[acme]
        config.require_tenant true
        config.strict_mode true
      end

      # Access through module
      expect(BetterTenant.configuration[:strategy]).to eq(:column)
      expect(BetterTenant.configuration[:tenant_column]).to eq(:org_id)

      # Access through Tenant class
      expect(BetterTenant::Tenant.configuration[:strategy]).to eq(:column)
      expect(BetterTenant::Tenant.configuration[:require_tenant]).to be true
      expect(BetterTenant::Tenant.configuration[:strict_mode]).to be true
    end
  end

  describe "reset functionality" do
    it "properly resets all state" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme]
        config.require_tenant false
      end

      BetterTenant::Tenant.switch!("acme")
      expect(BetterTenant::Tenant.current).to eq("acme")

      # Reset everything
      BetterTenant.reset!

      # Should raise configuration error
      expect {
        BetterTenant::Tenant.current
      }.to raise_error(BetterTenant::Errors::ConfigurationError)

      expect {
        BetterTenant.configuration
      }.to raise_error(BetterTenant::Errors::ConfigurationError)
    end
  end

  describe "multi-strategy support" do
    describe "column strategy" do
      it "works with column strategy end-to-end" do
        BetterTenant.configure do |config|
          config.strategy :column
          config.tenant_column :organization_id
          config.tenant_names %w[org1 org2]
          config.require_tenant false
        end

        tenant_model = Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include BetterTenant::ActiveRecordExtension
        end

        BetterTenant::Tenant.switch("org1") do
          sql = tenant_model.all.to_sql
          expect(sql).to include("organization_id")
          expect(sql).to include("org1")
        end
      end
    end

    describe "schema strategy" do
      it "works with schema strategy end-to-end" do
        BetterTenant.configure do |config|
          config.strategy :schema
          config.tenant_names %w[acme globex]
          config.persistent_schemas %w[shared]
          config.schema_format "tenant_%{tenant}"
          config.require_tenant false
        end

        expect(BetterTenant::Tenant.configuration[:strategy]).to eq(:schema)
        expect(BetterTenant::Tenant.configuration[:persistent_schemas]).to eq(%w[shared])

        # Schema switching is tested through the adapter
        BetterTenant::Tenant.switch("acme") do
          expect(BetterTenant::Tenant.current).to eq("acme")
        end
      end
    end
  end

  describe "tenant_model configuration" do
    let(:mock_model) do
      Class.new do
        def self.name
          "Organization"
        end

        def self.pluck(column)
          %w[acme globex initech]
        end
      end
    end

    before do
      stub_const("Organization", mock_model)
    end

    it "auto-configures from tenant_model" do
      BetterTenant.configure do |config|
        config.strategy :schema
        config.tenant_model "Organization"
        config.tenant_identifier :slug
        config.persistent_schemas %w[shared]
        config.schema_format "tenant_%{tenant}"
      end

      # tenant_names should be a Proc that queries the model
      expect(BetterTenant::Tenant.tenant_names).to eq(%w[acme globex initech])

      # Organization should be auto-excluded
      expect(BetterTenant::Tenant.excluded_model?("Organization")).to be true
    end
  end
end
