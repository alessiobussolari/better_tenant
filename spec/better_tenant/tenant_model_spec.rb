# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant tenant_model configuration" do
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

  describe "tenant_model configuration" do
    it "accepts a string class name" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
      end

      expect(config.to_h[:tenant_model]).to eq("Organization")
    end

    it "defaults tenant_identifier to :id" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
      end

      expect(config.to_h[:tenant_identifier]).to eq(:id)
    end

    it "allows custom tenant_identifier" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier :slug
      end

      expect(config.to_h[:tenant_identifier]).to eq(:slug)
    end

    it "converts string tenant_identifier to symbol" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier "subdomain"
      end

      expect(config.to_h[:tenant_identifier]).to eq(:subdomain)
    end
  end

  describe "automatic excluded_models" do
    it "auto-adds tenant_model to excluded_models" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
      end

      expect(config.to_h[:excluded_models]).to include("Organization")
    end

    it "does not duplicate if already in excluded_models" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.excluded_models %w[Organization User]
      end

      expect(config.to_h[:excluded_models]).to eq(%w[Organization User])
    end

    it "appends to existing excluded_models" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.excluded_models %w[User Admin]
        c.tenant_model "Organization"
      end

      expect(config.to_h[:excluded_models]).to eq(%w[User Admin Organization])
    end
  end

  describe "automatic tenant_names Proc" do
    # Create a mock model class for testing
    let(:mock_model) do
      Class.new do
        def self.name
          "Organization"
        end

        def self.pluck(column)
          case column
          when :id then [1, 2, 3]
          when :slug then %w[acme globex initech]
          when :subdomain then %w[acme-corp globex-inc]
          end
        end
      end
    end

    before do
      stub_const("Organization", mock_model)
    end

    it "creates a Proc for tenant_names when tenant_model is set" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier :slug
      end

      tenant_names = config.to_h[:tenant_names]
      expect(tenant_names).to be_a(Proc)
    end

    it "Proc returns tenant identifiers as strings" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier :slug
      end

      tenant_names = config.to_h[:tenant_names]
      expect(tenant_names.call).to eq(%w[acme globex initech])
    end

    it "Proc converts numeric ids to strings" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier :id
      end

      tenant_names = config.to_h[:tenant_names]
      expect(tenant_names.call).to eq(%w[1 2 3])
    end

    it "does not override explicit tenant_names" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[custom1 custom2]
        c.tenant_model "Organization"
      end

      # Explicit tenant_names takes precedence
      expect(config.to_h[:tenant_names]).to eq(%w[custom1 custom2])
    end
  end

  describe "integration with Tenant" do
    let(:mock_model) do
      Class.new do
        def self.name
          "Organization"
        end

        def self.pluck(column)
          %w[acme globex]
        end
      end
    end

    before do
      stub_const("Organization", mock_model)
    end

    it "works with BetterTenant.configure" do
      BetterTenant.configure do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier :slug
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
      end

      expect(BetterTenant::Tenant.configuration[:tenant_model]).to eq("Organization")
      expect(BetterTenant::Tenant.configuration[:excluded_models]).to include("Organization")
    end

    it "tenant_names Proc works through Tenant.tenant_names" do
      BetterTenant.configure do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier :slug
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
      end

      expect(BetterTenant::Tenant.tenant_names).to eq(%w[acme globex])
    end

    it "exists? validates against model data" do
      BetterTenant.configure do |c|
        c.strategy :schema
        c.tenant_model "Organization"
        c.tenant_identifier :slug
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
      end

      expect(BetterTenant::Tenant.exists?("acme")).to be true
      expect(BetterTenant::Tenant.exists?("unknown")).to be false
    end
  end

  describe "different tenant_identifier columns" do
    let(:mock_model) do
      Class.new do
        def self.name
          "Tenant"
        end

        def self.pluck(column)
          case column
          when :name then ["Acme Corp", "Globex Inc"]
          when :database_name then %w[acme_db globex_db]
          when :uuid then %w[uuid-1 uuid-2]
          end
        end
      end
    end

    before do
      stub_const("Tenant", mock_model)
    end

    it "works with :name identifier" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Tenant"
        c.tenant_identifier :name
      end

      expect(config.to_h[:tenant_names].call).to eq(["Acme Corp", "Globex Inc"])
    end

    it "works with :database_name identifier" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Tenant"
        c.tenant_identifier :database_name
      end

      expect(config.to_h[:tenant_names].call).to eq(%w[acme_db globex_db])
    end

    it "works with :uuid identifier" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_model "Tenant"
        c.tenant_identifier :uuid
      end

      expect(config.to_h[:tenant_names].call).to eq(%w[uuid-1 uuid-2])
    end
  end

  describe "without tenant_model" do
    it "tenant_names remains as configured array" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex]
      end

      expect(config.to_h[:tenant_names]).to eq(%w[acme globex])
      expect(config.to_h[:tenant_model]).to be_nil
    end

    it "excluded_models remains as configured" do
      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex]
        c.excluded_models %w[User]
      end

      expect(config.to_h[:excluded_models]).to eq(%w[User])
    end
  end
end
