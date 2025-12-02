# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Errors::TenantContextMissingError do
  describe "inheritance" do
    it "inherits from TenantError" do
      expect(described_class).to be < BetterTenant::Errors::TenantError
    end
  end

  describe "instantiation" do
    subject(:error) { described_class.new(operation: :query, model_class: "Article") }

    it "sets the operation attribute" do
      expect(error.operation).to eq(:query)
    end

    it "sets the model_class attribute" do
      expect(error.model_class).to eq("Article")
    end

    it "generates a descriptive message" do
      expect(error.message).to include("No tenant context")
      expect(error.message).to include("query")
    end
  end

  describe "instantiation with default values" do
    subject(:error) { described_class.new }

    it "has default operation" do
      expect(error.operation).to eq(:unknown)
    end

    it "has default model_class" do
      expect(error.model_class).to be_nil
    end
  end

  describe "Sentry-compatible attributes" do
    subject(:error) { described_class.new(operation: :create, model_class: "User") }

    describe "#tags" do
      it "returns error_category tag" do
        expect(error.tags[:error_category]).to eq("tenant_context_missing")
      end

      it "returns module tag" do
        expect(error.tags[:module]).to eq("better_tenant")
      end

      it "returns operation tag" do
        expect(error.tags[:operation]).to eq("create")
      end
    end

    describe "#context" do
      it "returns model_class" do
        expect(error.context[:model_class]).to eq("User")
      end
    end

    describe "#extra" do
      it "returns operation" do
        expect(error.extra[:operation]).to eq(:create)
      end

      it "returns model_class" do
        expect(error.extra[:model_class]).to eq("User")
      end
    end
  end
end
