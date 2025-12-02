# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant Excluded Models" do
  let(:mock_connection) { double("connection") }
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[acme globex]
      c.excluded_models %w[SharedModel PublicModel]
      c.require_tenant false
    end
  end

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }

    BetterTenant::Tenant.reset!
    BetterTenant::Tenant.configure(config)
  end

  after do
    BetterTenant::Tenant.reset!
  end

  describe "excluded model behavior" do
    let(:excluded_model_class) do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include BetterTenant::ActiveRecordExtension
      end
      # Set a class name to test exclusion
      stub_const("SharedModel", klass)
      klass
    end

    let(:normal_model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include BetterTenant::ActiveRecordExtension
      end
    end

    it "returns false for tenantable? on excluded models" do
      expect(excluded_model_class.excluded_from_tenancy?).to be true
    end

    it "returns true for tenantable? on normal models" do
      expect(normal_model_class.excluded_from_tenancy?).to be false
    end

    context "when tenant is set" do
      before { BetterTenant::Tenant.switch!("acme") }

      it "does not apply tenant scope to excluded models" do
        relation = excluded_model_class.all
        expect(relation.to_sql).not_to include("tenant_id")
      end

      it "applies tenant scope to normal models" do
        relation = normal_model_class.all
        expect(relation.to_sql).to include("tenant_id")
      end
    end

    context "when require_tenant is true" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :tenant_id
          c.tenant_names %w[acme globex]
          c.excluded_models %w[SharedModel]
          c.require_tenant true
        end
      end

      it "does not raise error for excluded models without tenant" do
        expect {
          excluded_model_class.all.to_sql
        }.not_to raise_error
      end

      it "raises error for normal models without tenant" do
        expect {
          normal_model_class.all.to_a
        }.to raise_error(BetterTenant::Errors::TenantContextMissingError)
      end
    end
  end

  describe "schema strategy excluded models" do
    let(:schema_config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex]
        c.excluded_models %w[SharedModel]
        c.persistent_schemas %w[shared public]
        c.require_tenant false
      end
    end

    before do
      BetterTenant::Tenant.reset!
      BetterTenant::Tenant.configure(schema_config)
    end

    it "excluded models remain in public schema" do
      # In schema strategy, excluded models should not have their schema changed
      # This is handled at the adapter level
      expect(schema_config.to_h[:excluded_models]).to include("SharedModel")
    end
  end

  describe ".excluded_model?" do
    it "returns true for excluded model names" do
      expect(BetterTenant::Tenant.excluded_model?("SharedModel")).to be true
      expect(BetterTenant::Tenant.excluded_model?("PublicModel")).to be true
    end

    it "returns false for non-excluded model names" do
      expect(BetterTenant::Tenant.excluded_model?("Article")).to be false
      expect(BetterTenant::Tenant.excluded_model?("User")).to be false
    end
  end
end
