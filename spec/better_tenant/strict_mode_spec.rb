# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant strict_mode" do
  let(:mock_connection) { double("connection") }

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }
  end

  after do
    BetterTenant::Tenant.reset!
  end

  describe "configuration" do
    it "defaults to false" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :column
        c.tenant_names %w[acme]
      end

      expect(config.to_h[:strict_mode]).to be false
    end

    it "can be enabled" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :column
        c.tenant_names %w[acme]
        c.strict_mode true
      end

      expect(config.to_h[:strict_mode]).to be true
    end

    it "can be disabled explicitly" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :column
        c.tenant_names %w[acme]
        c.strict_mode false
      end

      expect(config.to_h[:strict_mode]).to be false
    end

    it "raises ConfigurationError for non-boolean value" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :column
        c.tenant_names %w[acme]
      end

      expect {
        config.strict_mode "yes"
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be a boolean/)
    end
  end

  describe "strict_mode in Tenant configuration" do
    context "when strict_mode is enabled" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_names %w[acme globex]
          c.strict_mode true
        end
        BetterTenant::Tenant.configure(config)
      end

      it "stores strict_mode in configuration" do
        expect(BetterTenant::Tenant.configuration[:strict_mode]).to be true
      end
    end

    context "when strict_mode is disabled" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_names %w[acme globex]
          c.strict_mode false
        end
        BetterTenant::Tenant.configure(config)
      end

      it "stores strict_mode as false" do
        expect(BetterTenant::Tenant.configuration[:strict_mode]).to be false
      end
    end

    context "with schema strategy" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex]
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
          c.strict_mode true
        end
        BetterTenant::Tenant.configure(config)
      end

      it "stores strict_mode with schema strategy" do
        expect(BetterTenant::Tenant.configuration[:strict_mode]).to be true
      end
    end
  end
end
