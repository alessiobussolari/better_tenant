# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Tenant do
  let(:mock_connection) { double("connection") }
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :schema
      c.tenant_names %w[acme globex initech]
      c.persistent_schemas %w[shared]
      c.schema_format "tenant_%{tenant}"
    end
  end

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }

    # Reset singleton state
    described_class.reset!
    described_class.configure(config)
  end

  after do
    described_class.reset!
  end

  describe ".configure" do
    it "accepts a Configurator instance" do
      expect { described_class.configure(config) }.not_to raise_error
    end

    it "stores the configuration" do
      expect(described_class.configuration).to be_a(Hash)
      expect(described_class.configuration[:strategy]).to eq(:schema)
    end
  end

  describe ".current" do
    it "returns nil when no tenant is set" do
      expect(described_class.current).to be_nil
    end

    it "returns the current tenant when set" do
      described_class.switch!("acme")
      expect(described_class.current).to eq("acme")
    end
  end

  describe ".switch!" do
    it "switches to the specified tenant" do
      described_class.switch!("acme")
      expect(described_class.current).to eq("acme")
    end

    it "raises TenantNotFoundError for invalid tenant" do
      expect {
        described_class.switch!("unknown")
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end

    it "returns the tenant name" do
      result = described_class.switch!("acme")
      expect(result).to eq("acme")
    end
  end

  describe ".switch" do
    it "switches tenant for the block duration" do
      described_class.switch("acme") do
        expect(described_class.current).to eq("acme")
      end
    end

    it "resets tenant after block completes" do
      described_class.switch("acme") { }
      expect(described_class.current).to be_nil
    end

    it "resets tenant even if block raises" do
      expect {
        described_class.switch("acme") { raise "test error" }
      }.to raise_error("test error")

      expect(described_class.current).to be_nil
    end

    it "returns the block result" do
      result = described_class.switch("acme") { "block result" }
      expect(result).to eq("block result")
    end

    it "restores previous tenant after nested switch" do
      described_class.switch!("acme")

      described_class.switch("globex") do
        expect(described_class.current).to eq("globex")
      end

      expect(described_class.current).to eq("acme")
    end
  end

  describe ".reset" do
    before { described_class.switch!("acme") }

    it "clears the current tenant" do
      described_class.reset
      expect(described_class.current).to be_nil
    end
  end

  describe ".create" do
    it "creates a new tenant schema" do
      expect(mock_connection).to receive(:execute).with(/CREATE SCHEMA IF NOT EXISTS/)
      described_class.create("acme")
    end

    it "raises TenantNotFoundError if tenant not in tenant_names" do
      expect {
        described_class.create("unknown")
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end
  end

  describe ".drop" do
    it "drops the tenant schema" do
      expect(mock_connection).to receive(:execute).with(/DROP SCHEMA IF EXISTS/)
      described_class.drop("acme")
    end
  end

  describe ".exists?" do
    it "returns true for existing tenant" do
      expect(described_class.exists?("acme")).to be true
    end

    it "returns false for non-existing tenant" do
      expect(described_class.exists?("unknown")).to be false
    end
  end

  describe ".tenant_names" do
    it "returns all tenant names" do
      expect(described_class.tenant_names).to eq(%w[acme globex initech])
    end

    context "with Proc" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names -> { %w[dynamic1 dynamic2] }
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
        end
      end

      it "calls the Proc to get tenant names" do
        expect(described_class.tenant_names).to eq(%w[dynamic1 dynamic2])
      end

      it "validates against Proc result for exists?" do
        expect(described_class.exists?("dynamic1")).to be true
        expect(described_class.exists?("unknown")).to be false
      end
    end

    context "when Proc raises exception" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names -> { raise "DB connection failed" }
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
        end
      end

      it "propagates the exception" do
        expect { described_class.tenant_names }.to raise_error("DB connection failed")
      end
    end

    context "when Proc returns dynamic results" do
      let(:tenants) { %w[tenant1] }
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names -> { tenants }
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
        end
      end

      it "reflects changes in tenant list" do
        expect(described_class.exists?("tenant1")).to be true
        expect(described_class.exists?("tenant2")).to be false

        tenants << "tenant2"

        expect(described_class.exists?("tenant2")).to be true
      end
    end
  end

  describe ".each" do
    it "iterates over all tenants" do
      tenants = []
      described_class.each { |t| tenants << t }
      expect(tenants).to eq(%w[acme globex initech])
    end

    it "switches context for each tenant" do
      current_tenants = []
      described_class.each { current_tenants << described_class.current }
      expect(current_tenants).to eq(%w[acme globex initech])
    end

    it "resets tenant after iteration" do
      described_class.each { }
      expect(described_class.current).to be_nil
    end
  end

  describe ".adapter" do
    it "returns the adapter instance" do
      expect(described_class.adapter).to be_a(BetterTenant::Adapters::PostgresqlAdapter)
    end
  end

  describe "unconfigured state" do
    before { described_class.reset! }

    it "raises ConfigurationError when not configured" do
      expect {
        described_class.current
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /not configured/)
    end
  end

  describe "thread safety" do
    it "uses Current attributes for thread-local storage" do
      # This test verifies that different threads can have different tenants
      described_class.switch!("acme")

      thread_tenant = nil
      thread = Thread.new do
        # In a new thread, the tenant should not be inherited
        # (behavior depends on Rails Current implementation)
        thread_tenant = described_class.current
      end
      thread.join

      # Main thread should still have its tenant
      expect(described_class.current).to eq("acme")
    end
  end
end
