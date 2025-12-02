# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Errors::TenantNotFoundError do
  describe "inheritance" do
    it "inherits from TenantError" do
      expect(described_class).to be < BetterTenant::Errors::TenantError
    end
  end

  describe "instantiation" do
    subject(:error) { described_class.new(tenant_name: "acme") }

    it "sets the tenant_name attribute" do
      expect(error.tenant_name).to eq("acme")
    end

    it "generates a descriptive message" do
      expect(error.message).to eq("Tenant 'acme' not found")
    end
  end

  describe "Sentry-compatible attributes" do
    subject(:error) { described_class.new(tenant_name: "unknown_tenant") }

    describe "#tags" do
      it "returns error_category tag" do
        expect(error.tags[:error_category]).to eq("tenant_not_found")
      end

      it "returns module tag" do
        expect(error.tags[:module]).to eq("better_tenant")
      end

      it "returns tenant tag" do
        expect(error.tags[:tenant]).to eq("unknown_tenant")
      end
    end

    describe "#context" do
      it "returns empty hash (no model context)" do
        expect(error.context).to eq({})
      end
    end

    describe "#extra" do
      it "returns tenant_name" do
        expect(error.extra[:tenant_name]).to eq("unknown_tenant")
      end
    end
  end
end
