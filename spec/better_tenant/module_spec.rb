# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant do
  let(:mock_connection) { double("connection") }

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }
  end

  after do
    BetterTenant.reset!
  end

  describe ".configure" do
    it "accepts a configuration block" do
      expect {
        BetterTenant.configure do |config|
          config.strategy :column
          config.tenant_column :tenant_id
          config.tenant_names %w[acme globex]
        end
      }.not_to raise_error
    end

    it "yields a Configurator instance" do
      BetterTenant.configure do |config|
        expect(config).to be_a(BetterTenant::Configurator)
      end
    end

    it "applies configuration to Tenant" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :organization_id
        config.tenant_names %w[test]
      end

      expect(BetterTenant::Tenant.configuration[:tenant_column]).to eq(:organization_id)
    end

    it "can be called multiple times" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[first]
      end

      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :org_id
        config.tenant_names %w[second]
      end

      expect(BetterTenant::Tenant.configuration[:tenant_column]).to eq(:org_id)
    end

    it "works without a block" do
      expect { BetterTenant.configure }.not_to raise_error
    end
  end

  describe ".configuration" do
    it "returns the current configuration hash" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme]
        config.require_tenant false
      end

      config = BetterTenant.configuration
      expect(config).to be_a(Hash)
      expect(config[:strategy]).to eq(:column)
      expect(config[:tenant_column]).to eq(:tenant_id)
      expect(config[:require_tenant]).to be false
    end

    it "delegates to Tenant.configuration" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme]
      end

      expect(BetterTenant.configuration).to eq(BetterTenant::Tenant.configuration)
    end

    it "raises error when not configured" do
      BetterTenant.reset!
      expect { BetterTenant.configuration }.to raise_error(BetterTenant::Errors::ConfigurationError)
    end
  end

  describe ".reset!" do
    it "clears the configuration" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme]
      end

      BetterTenant.reset!

      expect { BetterTenant.configuration }.to raise_error(BetterTenant::Errors::ConfigurationError)
    end

    it "clears current tenant" do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme]
        config.require_tenant false
      end

      BetterTenant::Tenant.switch!("acme")
      BetterTenant.reset!

      expect { BetterTenant::Tenant.current }.to raise_error(BetterTenant::Errors::ConfigurationError)
    end
  end

  describe "module structure" do
    it "has a VERSION constant" do
      expect(BetterTenant::VERSION).to be_a(String)
      expect(BetterTenant::VERSION).to match(/\d+\.\d+\.\d+/)
    end

    it "has Configurator class" do
      expect(BetterTenant::Configurator).to be_a(Class)
    end

    it "has Tenant class" do
      expect(BetterTenant::Tenant).to be_a(Class)
    end

    it "has Middleware class" do
      expect(BetterTenant::Middleware).to be_a(Class)
    end

    it "has ActiveRecordExtension module" do
      expect(BetterTenant::ActiveRecordExtension).to be_a(Module)
    end

    it "has ActiveJobExtension module" do
      expect(BetterTenant::ActiveJobExtension).to be_a(Module)
    end

    it "has AuditLogger class" do
      expect(BetterTenant::AuditLogger).to be_a(Class)
    end
  end

  describe "error classes" do
    it "has TenantError base class" do
      expect(BetterTenant::Errors::TenantError).to be < StandardError
    end

    it "has ConfigurationError class" do
      # ConfigurationError inherits from ArgumentError for backward compatibility
      expect(BetterTenant::Errors::ConfigurationError).to be < ArgumentError
    end

    it "has TenantNotFoundError class" do
      expect(BetterTenant::Errors::TenantNotFoundError).to be < BetterTenant::Errors::TenantError
    end

    it "has TenantContextMissingError class" do
      expect(BetterTenant::Errors::TenantContextMissingError).to be < BetterTenant::Errors::TenantError
    end

    it "has TenantMismatchError class" do
      expect(BetterTenant::Errors::TenantMismatchError).to be < BetterTenant::Errors::TenantError
    end

    it "has TenantImmutableError class" do
      expect(BetterTenant::Errors::TenantImmutableError).to be < BetterTenant::Errors::TenantError
    end

    it "has SchemaNotFoundError class" do
      expect(BetterTenant::Errors::SchemaNotFoundError).to be < BetterTenant::Errors::TenantError
    end
  end

  describe "adapter classes" do
    it "has AbstractAdapter class" do
      expect(BetterTenant::Adapters::AbstractAdapter).to be_a(Class)
    end

    it "has PostgresqlAdapter class" do
      expect(BetterTenant::Adapters::PostgresqlAdapter).to be < BetterTenant::Adapters::AbstractAdapter
    end

    it "has ColumnAdapter class" do
      expect(BetterTenant::Adapters::ColumnAdapter).to be < BetterTenant::Adapters::AbstractAdapter
    end
  end

  describe "convenience methods integration" do
    before do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names %w[acme globex]
        config.require_tenant false
      end
    end

    it "allows switching tenants via Tenant.switch" do
      result = BetterTenant::Tenant.switch("acme") do
        BetterTenant::Tenant.current
      end

      expect(result).to eq("acme")
    end

    it "allows permanent switch via Tenant.switch!" do
      BetterTenant::Tenant.switch!("globex")
      expect(BetterTenant::Tenant.current).to eq("globex")
    end

    it "allows reset via Tenant.reset" do
      BetterTenant::Tenant.switch!("acme")
      BetterTenant::Tenant.reset
      expect(BetterTenant::Tenant.current).to be_nil
    end

    it "provides tenant_names list" do
      expect(BetterTenant::Tenant.tenant_names).to eq(%w[acme globex])
    end

    it "checks if tenant exists" do
      expect(BetterTenant::Tenant.exists?("acme")).to be true
      expect(BetterTenant::Tenant.exists?("unknown")).to be false
    end
  end
end
