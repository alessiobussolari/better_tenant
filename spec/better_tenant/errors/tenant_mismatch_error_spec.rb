# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Errors::TenantMismatchError do
  describe "inheritance" do
    it "inherits from TenantError" do
      expect(described_class).to be < BetterTenant::Errors::TenantError
    end
  end

  describe "instantiation" do
    subject(:error) do
      described_class.new(
        expected_tenant_id: "acme",
        actual_tenant_id: "globex",
        operation: :find,
        model_class: "Article"
      )
    end

    it "sets the expected_tenant_id attribute" do
      expect(error.expected_tenant_id).to eq("acme")
    end

    it "sets the actual_tenant_id attribute" do
      expect(error.actual_tenant_id).to eq("globex")
    end

    it "sets the operation attribute" do
      expect(error.operation).to eq(:find)
    end

    it "sets the model_class attribute" do
      expect(error.model_class).to eq("Article")
    end

    it "generates a descriptive message" do
      expect(error.message).to include("acme")
      expect(error.message).to include("globex")
      expect(error.message).to include("find")
    end
  end

  describe "Sentry-compatible attributes" do
    subject(:error) do
      described_class.new(
        expected_tenant_id: "tenant_a",
        actual_tenant_id: "tenant_b",
        operation: :update,
        model_class: "Comment"
      )
    end

    describe "#tags" do
      it "returns error_category tag" do
        expect(error.tags[:error_category]).to eq("tenant_mismatch")
      end

      it "returns module tag" do
        expect(error.tags[:module]).to eq("better_tenant")
      end

      it "returns operation tag" do
        expect(error.tags[:operation]).to eq("update")
      end
    end

    describe "#context" do
      it "returns model_class" do
        expect(error.context[:model_class]).to eq("Comment")
      end
    end

    describe "#extra" do
      it "returns expected_tenant_id" do
        expect(error.extra[:expected_tenant_id]).to eq("tenant_a")
      end

      it "returns actual_tenant_id" do
        expect(error.extra[:actual_tenant_id]).to eq("tenant_b")
      end

      it "returns operation" do
        expect(error.extra[:operation]).to eq(:update)
      end
    end
  end
end
