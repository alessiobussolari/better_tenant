# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Errors::TenantError do
  describe "inheritance" do
    it "inherits from StandardError" do
      expect(described_class).to be < StandardError
    end
  end

  describe "instantiation" do
    it "can be raised with a message" do
      expect { raise described_class, "Test error" }.to raise_error(described_class, "Test error")
    end
  end
end
