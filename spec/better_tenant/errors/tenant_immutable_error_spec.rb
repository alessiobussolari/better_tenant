# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Errors::TenantImmutableError do
  describe "inheritance" do
    it "inherits from TenantError" do
      expect(described_class).to be < BetterTenant::Errors::TenantError
    end
  end

  describe "instantiation" do
    subject(:error) do
      described_class.new(
        tenant_column: :tenant_id,
        model_class: "Article",
        record_id: 123
      )
    end

    it "sets the tenant_column attribute" do
      expect(error.tenant_column).to eq(:tenant_id)
    end

    it "sets the model_class attribute" do
      expect(error.model_class).to eq("Article")
    end

    it "sets the record_id attribute" do
      expect(error.record_id).to eq(123)
    end

    it "generates a descriptive message" do
      expect(error.message).to include("tenant_id")
      expect(error.message).to include("immutable")
    end
  end

  describe "instantiation without record_id" do
    subject(:error) do
      described_class.new(
        tenant_column: :tenant_id,
        model_class: "Article"
      )
    end

    it "has nil record_id" do
      expect(error.record_id).to be_nil
    end
  end

  describe "Sentry-compatible attributes" do
    subject(:error) do
      described_class.new(
        tenant_column: :organization_id,
        model_class: "Project",
        record_id: 456
      )
    end

    describe "#tags" do
      it "returns error_category tag" do
        expect(error.tags[:error_category]).to eq("tenant_immutable")
      end

      it "returns module tag" do
        expect(error.tags[:module]).to eq("better_tenant")
      end
    end

    describe "#context" do
      it "returns model_class" do
        expect(error.context[:model_class]).to eq("Project")
      end

      it "returns record_id" do
        expect(error.context[:record_id]).to eq(456)
      end
    end

    describe "#extra" do
      it "returns tenant_column" do
        expect(error.extra[:tenant_column]).to eq(:organization_id)
      end

      it "returns model_class" do
        expect(error.extra[:model_class]).to eq("Project")
      end

      it "returns record_id" do
        expect(error.extra[:record_id]).to eq(456)
      end
    end
  end
end
