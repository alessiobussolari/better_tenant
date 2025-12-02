# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Errors::ConfigurationError do
  describe "inheritance" do
    it "inherits from ArgumentError for backward compatibility" do
      expect(described_class).to be < ArgumentError
    end

    it "does not inherit from TenantError" do
      expect(described_class).not_to be < BetterTenant::Errors::TenantError
    end
  end

  describe "instantiation" do
    it "can be raised with a message" do
      expect { raise described_class, "Invalid configuration" }.to raise_error(
        described_class, "Invalid configuration"
      )
    end

    it "can be rescued as ArgumentError" do
      expect {
        begin
          raise described_class, "Test"
        rescue ArgumentError => e
          raise "Caught: #{e.message}"
        end
      }.to raise_error("Caught: Test")
    end
  end
end
