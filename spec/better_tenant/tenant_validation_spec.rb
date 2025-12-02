# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant Tenant Validation" do
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

  describe "tenant name validation" do
    context "with schema strategy" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme Globex INITECH]
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
        end
        BetterTenant::Tenant.configure(config)
      end

      it "is case-sensitive for exists?" do
        expect(BetterTenant::Tenant.exists?("acme")).to be true
        expect(BetterTenant::Tenant.exists?("ACME")).to be false
        expect(BetterTenant::Tenant.exists?("Globex")).to be true
        expect(BetterTenant::Tenant.exists?("globex")).to be false
      end

      it "is case-sensitive for switch!" do
        expect { BetterTenant::Tenant.switch!("acme") }.not_to raise_error
        expect { BetterTenant::Tenant.switch!("ACME") }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
      end
    end

    context "with column strategy" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :tenant_id
          c.tenant_names %w[acme Globex]
        end
        BetterTenant::Tenant.configure(config)
      end

      it "is case-sensitive for exists?" do
        expect(BetterTenant::Tenant.exists?("acme")).to be true
        expect(BetterTenant::Tenant.exists?("ACME")).to be false
      end
    end

    context "with special characters in tenant names" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme-corp tenant_123 my.tenant]
          c.persistent_schemas %w[shared]
          c.schema_format "%{tenant}"
        end
        BetterTenant::Tenant.configure(config)
      end

      it "accepts hyphens in tenant names" do
        expect(BetterTenant::Tenant.exists?("acme-corp")).to be true
      end

      it "accepts underscores in tenant names" do
        expect(BetterTenant::Tenant.exists?("tenant_123")).to be true
      end

      it "accepts dots in tenant names" do
        expect(BetterTenant::Tenant.exists?("my.tenant")).to be true
      end

      it "can switch to tenant with special characters" do
        expect { BetterTenant::Tenant.switch!("acme-corp") }.not_to raise_error
        expect(BetterTenant::Tenant.current).to eq("acme-corp")
      end
    end

    context "with empty or whitespace tenant names" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme]
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
        end
        BetterTenant::Tenant.configure(config)
      end

      it "returns false for empty string" do
        expect(BetterTenant::Tenant.exists?("")).to be false
      end

      it "returns false for whitespace" do
        expect(BetterTenant::Tenant.exists?("  ")).to be false
      end

      it "returns false for nil" do
        expect(BetterTenant::Tenant.exists?(nil)).to be false
      end
    end

    context "with numeric tenant identifiers" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :tenant_id
          c.tenant_names %w[1 2 123]
        end
        BetterTenant::Tenant.configure(config)
      end

      it "accepts numeric strings as tenant names" do
        expect(BetterTenant::Tenant.exists?("1")).to be true
        expect(BetterTenant::Tenant.exists?("123")).to be true
      end

      it "can switch to numeric tenant" do
        expect { BetterTenant::Tenant.switch!("1") }.not_to raise_error
        expect(BetterTenant::Tenant.current).to eq("1")
      end
    end
  end

  describe "tenant name in different strategies" do
    context "schema strategy validates against schema naming rules" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[valid_tenant]
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
        end
        BetterTenant::Tenant.configure(config)
      end

      it "exists? returns true for valid tenant" do
        expect(BetterTenant::Tenant.exists?("valid_tenant")).to be true
      end
    end

    context "column strategy is more flexible with naming" do
      before do
        config = BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :tenant_id
          c.tenant_names ["tenant with spaces", "tenant@special"]
        end
        BetterTenant::Tenant.configure(config)
      end

      it "accepts tenant names with spaces in column strategy" do
        expect(BetterTenant::Tenant.exists?("tenant with spaces")).to be true
      end

      it "accepts tenant names with special chars in column strategy" do
        expect(BetterTenant::Tenant.exists?("tenant@special")).to be true
      end
    end
  end
end
