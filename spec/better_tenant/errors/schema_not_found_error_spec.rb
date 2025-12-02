# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Errors::SchemaNotFoundError do
  describe "inheritance" do
    it "inherits from TenantError" do
      expect(described_class).to be < BetterTenant::Errors::TenantError
    end
  end

  describe "instantiation" do
    subject(:error) do
      described_class.new(
        schema_name: "tenant_acme",
        tenant_name: "acme"
      )
    end

    it "sets the schema_name attribute" do
      expect(error.schema_name).to eq("tenant_acme")
    end

    it "sets the tenant_name attribute" do
      expect(error.tenant_name).to eq("acme")
    end

    it "generates a descriptive message" do
      expect(error.message).to include("tenant_acme")
      expect(error.message).to include("schema")
    end
  end

  describe "instantiation without tenant_name" do
    subject(:error) do
      described_class.new(schema_name: "missing_schema")
    end

    it "has nil tenant_name" do
      expect(error.tenant_name).to be_nil
    end

    it "still generates a message" do
      expect(error.message).to include("missing_schema")
    end
  end

  describe "Sentry-compatible attributes" do
    subject(:error) do
      described_class.new(
        schema_name: "tenant_globex",
        tenant_name: "globex"
      )
    end

    describe "#tags" do
      it "returns error_category tag" do
        expect(error.tags[:error_category]).to eq("schema_not_found")
      end

      it "returns module tag" do
        expect(error.tags[:module]).to eq("better_tenant")
      end

      it "returns tenant tag" do
        expect(error.tags[:tenant]).to eq("globex")
      end
    end

    describe "#context" do
      it "returns empty hash (no model context)" do
        expect(error.context).to eq({})
      end
    end

    describe "#extra" do
      it "returns schema_name" do
        expect(error.extra[:schema_name]).to eq("tenant_globex")
      end

      it "returns tenant_name" do
        expect(error.extra[:tenant_name]).to eq("globex")
      end
    end
  end
end
