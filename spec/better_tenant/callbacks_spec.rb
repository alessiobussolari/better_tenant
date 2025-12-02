# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant Callback Exception Handling" do
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

  describe "before_switch callback exceptions" do
    let(:config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex]
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
        c.before_switch { |_from, _to| raise "before_switch failed" }
      end
    end

    before do
      BetterTenant::Tenant.reset!
      BetterTenant::Tenant.configure(config)
    end

    it "propagates exception from before_switch" do
      expect {
        BetterTenant::Tenant.switch!("acme")
      }.to raise_error("before_switch failed")
    end

    it "does not switch tenant when before_switch fails" do
      expect {
        BetterTenant::Tenant.switch!("acme") rescue nil
      }.not_to change { BetterTenant::Tenant.current }
    end
  end

  describe "after_switch callback exceptions" do
    let(:config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex]
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
        c.after_switch { |_from, _to| raise "after_switch failed" }
      end
    end

    before do
      BetterTenant::Tenant.reset!
      BetterTenant::Tenant.configure(config)
    end

    it "propagates exception from after_switch" do
      expect {
        BetterTenant::Tenant.switch!("acme")
      }.to raise_error("after_switch failed")
    end

    it "tenant is switched even when after_switch fails" do
      BetterTenant::Tenant.switch!("acme") rescue nil
      expect(BetterTenant::Tenant.current).to eq("acme")
    end
  end

  describe "before_create callback exceptions" do
    let(:config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex new_tenant]
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
        c.before_create { |_tenant| raise "before_create failed" }
      end
    end

    before do
      BetterTenant::Tenant.reset!
      BetterTenant::Tenant.configure(config)
    end

    it "propagates exception from before_create" do
      expect {
        BetterTenant::Tenant.create("new_tenant")
      }.to raise_error("before_create failed")
    end

    it "does not create schema when before_create fails" do
      expect(mock_connection).not_to receive(:execute).with(/CREATE SCHEMA/)
      BetterTenant::Tenant.create("new_tenant") rescue nil
    end
  end

  describe "after_create callback exceptions" do
    let(:config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex new_tenant]
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
        c.after_create { |_tenant| raise "after_create failed" }
      end
    end

    before do
      BetterTenant::Tenant.reset!
      BetterTenant::Tenant.configure(config)
    end

    it "propagates exception from after_create" do
      expect {
        BetterTenant::Tenant.create("new_tenant")
      }.to raise_error("after_create failed")
    end
  end

  describe "callback with arguments" do
    it "passes correct arguments to before_switch" do
      from_tenant = nil
      to_tenant = nil

      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex]
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
        c.before_switch do |from, to|
          from_tenant = from
          to_tenant = to
        end
      end

      BetterTenant::Tenant.reset!
      BetterTenant::Tenant.configure(config)

      BetterTenant::Tenant.switch!("acme")
      expect(from_tenant).to be_nil
      expect(to_tenant).to eq("acme")

      BetterTenant::Tenant.switch!("globex")
      expect(from_tenant).to eq("acme")
      expect(to_tenant).to eq("globex")
    end

    it "passes correct tenant to before_create" do
      created_tenant = nil

      config = BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex new_tenant]
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
        c.before_create { |tenant| created_tenant = tenant }
      end

      BetterTenant::Tenant.reset!
      BetterTenant::Tenant.configure(config)

      BetterTenant::Tenant.create("new_tenant")
      expect(created_tenant).to eq("new_tenant")
    end
  end
end
