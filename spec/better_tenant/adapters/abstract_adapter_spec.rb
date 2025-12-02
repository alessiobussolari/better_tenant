# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Adapters::AbstractAdapter do
  let(:config) do
    {
      strategy: :schema,
      tenant_column: :tenant_id,
      excluded_models: [],
      persistent_schemas: %w[shared],
      schema_format: "tenant_%{tenant}",
      callbacks: {}
    }
  end

  subject(:adapter) { described_class.new(config) }

  describe "#initialize" do
    it "stores the configuration" do
      expect(adapter.config).to eq(config)
    end

    it "starts with no current tenant" do
      expect(adapter.current).to be_nil
    end
  end

  describe "#switch!" do
    it "raises NotImplementedError" do
      expect { adapter.switch!("tenant") }.to raise_error(NotImplementedError)
    end
  end

  describe "#switch" do
    it "raises NotImplementedError" do
      expect { adapter.switch("tenant") { } }.to raise_error(NotImplementedError)
    end
  end

  describe "#reset" do
    it "raises NotImplementedError" do
      expect { adapter.reset }.to raise_error(NotImplementedError)
    end
  end

  describe "#create" do
    it "raises NotImplementedError" do
      expect { adapter.create("tenant") }.to raise_error(NotImplementedError)
    end
  end

  describe "#drop" do
    it "raises NotImplementedError" do
      expect { adapter.drop("tenant") }.to raise_error(NotImplementedError)
    end
  end

  describe "#exists?" do
    it "raises NotImplementedError" do
      expect { adapter.exists?("tenant") }.to raise_error(NotImplementedError)
    end
  end

  describe "#all_tenants" do
    context "when tenant_names is an array" do
      let(:config) { super().merge(tenant_names: %w[acme globex]) }

      it "returns the array" do
        expect(adapter.all_tenants).to eq(%w[acme globex])
      end
    end

    context "when tenant_names is a proc" do
      let(:config) { super().merge(tenant_names: -> { %w[dynamic1 dynamic2] }) }

      it "calls the proc" do
        expect(adapter.all_tenants).to eq(%w[dynamic1 dynamic2])
      end
    end
  end

  describe "#schema_for" do
    it "formats schema name using template" do
      expect(adapter.schema_for("acme")).to eq("tenant_acme")
    end

    context "with default format" do
      let(:config) { super().merge(schema_format: "%{tenant}") }

      it "returns tenant name directly" do
        expect(adapter.schema_for("acme")).to eq("acme")
      end
    end
  end

  describe "#validate_tenant!" do
    let(:config) { super().merge(tenant_names: %w[acme globex]) }

    it "passes for valid tenant" do
      expect { adapter.validate_tenant!("acme") }.not_to raise_error
    end

    it "raises TenantNotFoundError for invalid tenant" do
      expect {
        adapter.validate_tenant!("unknown")
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end
  end
end
