# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Adapters::PostgresqlAdapter do
  let(:config) do
    {
      strategy: :schema,
      tenant_column: :tenant_id,
      tenant_names: %w[acme globex],
      excluded_models: [],
      persistent_schemas: %w[shared],
      schema_format: "tenant_%{tenant}",
      callbacks: {
        before_create: nil,
        after_create: nil,
        before_switch: nil,
        after_switch: nil
      }
    }
  end

  # Mock connection to avoid actual SQL execution (SQLite doesn't support SET search_path)
  let(:mock_connection) { double("connection") }

  subject(:adapter) { described_class.new(config) }

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }
  end

  describe "inheritance" do
    it "inherits from AbstractAdapter" do
      expect(described_class).to be < BetterTenant::Adapters::AbstractAdapter
    end
  end

  describe "#initialize" do
    it "stores the configuration" do
      expect(adapter.config).to eq(config)
    end
  end

  describe "#switch!" do
    context "with valid tenant" do
      it "sets the current tenant" do
        adapter.switch!("acme")
        expect(adapter.current).to eq("acme")
      end

      it "executes SET search_path SQL" do
        expect(mock_connection).to receive(:execute).with(/SET search_path TO tenant_acme/)
        adapter.switch!("acme")
      end
    end

    context "with invalid tenant" do
      it "raises TenantNotFoundError" do
        expect {
          adapter.switch!("unknown")
        }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
      end
    end

    context "with callbacks" do
      let(:before_callback) { double("before_callback") }
      let(:after_callback) { double("after_callback") }
      let(:config) do
        super().merge(
          callbacks: {
            before_switch: ->(from, to) { before_callback.call(from, to) },
            after_switch: ->(from, to) { after_callback.call(from, to) }
          }
        )
      end

      it "calls before_switch callback" do
        expect(before_callback).to receive(:call).with(nil, "acme")
        allow(after_callback).to receive(:call)
        adapter.switch!("acme")
      end

      it "calls after_switch callback" do
        allow(before_callback).to receive(:call)
        expect(after_callback).to receive(:call).with(nil, "acme")
        adapter.switch!("acme")
      end
    end
  end

  describe "#switch" do
    it "switches tenant for block duration" do
      adapter.switch("acme") do
        expect(adapter.current).to eq("acme")
      end
    end

    it "resets tenant after block" do
      adapter.switch("acme") do
        # inside block
      end
      expect(adapter.current).to be_nil
    end

    it "resets tenant even if block raises" do
      expect {
        adapter.switch("acme") do
          raise "test error"
        end
      }.to raise_error("test error")

      expect(adapter.current).to be_nil
    end

    it "returns the block result" do
      result = adapter.switch("acme") { "block result" }
      expect(result).to eq("block result")
    end
  end

  describe "#reset" do
    before { adapter.switch!("acme") }

    it "clears the current tenant" do
      adapter.reset
      expect(adapter.current).to be_nil
    end

    it "executes SET search_path to default" do
      expect(mock_connection).to receive(:execute).with(/SET search_path TO shared, public/)
      adapter.reset
    end
  end

  describe "#exists?" do
    it "returns true for existing tenant" do
      expect(adapter.exists?("acme")).to be true
    end

    it "returns false for non-existing tenant" do
      expect(adapter.exists?("unknown")).to be false
    end
  end

  describe "#current_search_path" do
    it "builds search path with tenant schema" do
      adapter.switch!("acme")
      path = adapter.current_search_path

      expect(path).to include("tenant_acme")
      expect(path).to include("shared")
    end

    it "includes public schema" do
      adapter.switch!("acme")
      path = adapter.current_search_path

      expect(path).to include("public")
    end
  end

  describe "#default_search_path" do
    it "returns public schema path" do
      expect(adapter.default_search_path).to include("public")
    end

    it "includes persistent schemas" do
      expect(adapter.default_search_path).to include("shared")
    end
  end

  describe "#create" do
    it "validates tenant name" do
      # Even during creation, we validate the tenant exists in tenant_names
      config[:tenant_names] << "new_tenant"

      expect { adapter.create("new_tenant") }.not_to raise_error
    end

    it "executes CREATE SCHEMA SQL" do
      config[:tenant_names] << "new_tenant"
      expect(mock_connection).to receive(:execute).with(/CREATE SCHEMA IF NOT EXISTS/)
      adapter.create("new_tenant")
    end

    context "with callbacks" do
      let(:before_callback) { double("before_callback") }
      let(:after_callback) { double("after_callback") }
      let(:config) do
        super().merge(
          tenant_names: %w[acme globex new_tenant],
          callbacks: {
            before_create: ->(tenant) { before_callback.call(tenant) },
            after_create: ->(tenant) { after_callback.call(tenant) }
          }
        )
      end

      it "calls before_create callback" do
        expect(before_callback).to receive(:call).with("new_tenant")
        allow(after_callback).to receive(:call)
        adapter.create("new_tenant")
      end

      it "calls after_create callback" do
        allow(before_callback).to receive(:call)
        expect(after_callback).to receive(:call).with("new_tenant")
        adapter.create("new_tenant")
      end
    end
  end

  describe "#drop" do
    it "removes the tenant schema" do
      expect(mock_connection).to receive(:execute).with(/DROP SCHEMA IF EXISTS/)
      adapter.drop("acme")
    end
  end

  describe "#each_tenant" do
    it "iterates over all tenants" do
      tenants = []
      adapter.each_tenant { |t| tenants << t }
      expect(tenants).to eq(%w[acme globex])
    end

    it "switches to each tenant during iteration" do
      current_tenants = []
      adapter.each_tenant { current_tenants << adapter.current }
      expect(current_tenants).to eq(%w[acme globex])
    end

    it "resets tenant after iteration" do
      adapter.each_tenant { }
      expect(adapter.current).to be_nil
    end
  end

  describe "persistent_schemas integration" do
    context "with multiple persistent schemas" do
      let(:config) do
        {
          strategy: :schema,
          tenant_column: :tenant_id,
          tenant_names: %w[acme globex],
          excluded_models: [],
          persistent_schemas: %w[shared extensions audit],
          schema_format: "tenant_%{tenant}",
          callbacks: {}
        }
      end

      it "includes all persistent schemas in search_path" do
        adapter.switch!("acme")
        path = adapter.current_search_path

        expect(path).to include("shared")
        expect(path).to include("extensions")
        expect(path).to include("audit")
      end

      it "includes persistent schemas in default search path" do
        path = adapter.default_search_path

        expect(path).to include("shared")
        expect(path).to include("extensions")
        expect(path).to include("audit")
      end
    end

    context "with empty persistent_schemas" do
      let(:config) do
        {
          strategy: :schema,
          tenant_column: :tenant_id,
          tenant_names: %w[acme globex],
          excluded_models: [],
          persistent_schemas: [],
          schema_format: "tenant_%{tenant}",
          callbacks: {}
        }
      end

      it "only includes public schema in default path" do
        expect(adapter.default_search_path).to eq("public")
      end
    end
  end

  describe "schema_format rendering" do
    context "with prefix format" do
      let(:config) do
        {
          strategy: :schema,
          tenant_column: :tenant_id,
          tenant_names: %w[acme globex],
          excluded_models: [],
          persistent_schemas: %w[shared],
          schema_format: "customer_%{tenant}",
          callbacks: {}
        }
      end

      it "applies format to schema name" do
        expect(mock_connection).to receive(:execute).with(/SET search_path TO customer_acme/)
        adapter.switch!("acme")
      end
    end

    context "with suffix format" do
      let(:config) do
        {
          strategy: :schema,
          tenant_column: :tenant_id,
          tenant_names: %w[acme globex],
          excluded_models: [],
          persistent_schemas: %w[shared],
          schema_format: "%{tenant}_schema",
          callbacks: {}
        }
      end

      it "applies suffix format" do
        expect(mock_connection).to receive(:execute).with(/SET search_path TO acme_schema/)
        adapter.switch!("acme")
      end
    end

    context "with just tenant placeholder" do
      let(:config) do
        {
          strategy: :schema,
          tenant_column: :tenant_id,
          tenant_names: %w[acme globex],
          excluded_models: [],
          persistent_schemas: %w[shared],
          schema_format: "%{tenant}",
          callbacks: {}
        }
      end

      it "uses tenant name directly as schema" do
        expect(mock_connection).to receive(:execute).with(/SET search_path TO acme/)
        adapter.switch!("acme")
      end
    end

    context "with complex format" do
      let(:config) do
        {
          strategy: :schema,
          tenant_column: :tenant_id,
          tenant_names: %w[acme globex],
          excluded_models: [],
          persistent_schemas: %w[shared],
          schema_format: "app_%{tenant}_v1",
          callbacks: {}
        }
      end

      it "applies complex format correctly" do
        expect(mock_connection).to receive(:execute).with(/SET search_path TO app_acme_v1/)
        adapter.switch!("acme")
      end
    end
  end
end
