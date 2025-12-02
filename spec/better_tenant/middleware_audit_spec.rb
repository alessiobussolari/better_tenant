# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant Middleware Audit Logging" do
  let(:mock_connection) { double("connection") }
  let(:logger) { instance_double(Logger) }
  let(:app) { ->(env) { [200, env, "OK"] } }
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :schema
      c.tenant_names %w[acme globex]
      c.persistent_schemas %w[shared]
      c.schema_format "tenant_%{tenant}"
      c.require_tenant false
      c.audit_access true
      c.audit_violations true
    end
  end

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }
    allow(Rails).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)

    BetterTenant::Tenant.reset!
    BetterTenant::Tenant.configure(config)
  end

  after do
    BetterTenant::Tenant.reset!
  end

  describe "audit_access configuration" do
    context "when audit_access is enabled" do
      it "configuration stores audit_access as true" do
        expect(BetterTenant::Tenant.configuration[:audit_access]).to be true
      end
    end

    context "when audit_access is disabled" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex]
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
          c.require_tenant false
          c.audit_access false
          c.audit_violations false
        end
      end

      it "configuration stores audit_access as false" do
        expect(BetterTenant::Tenant.configuration[:audit_access]).to be false
      end
    end
  end

  describe "audit_violations configuration" do
    context "when audit_violations is enabled" do
      it "configuration stores audit_violations as true" do
        expect(BetterTenant::Tenant.configuration[:audit_violations]).to be true
      end
    end

    context "when audit_violations is disabled" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex]
          c.require_tenant false
          c.audit_violations false
        end
      end

      it "configuration stores audit_violations as false" do
        expect(BetterTenant::Tenant.configuration[:audit_violations]).to be false
      end
    end
  end

  describe "middleware request handling with audit enabled" do
    it "processes request successfully with valid tenant" do
      env = Rack::MockRequest.env_for("http://acme.example.com/")
      status, _headers, _body = BetterTenant::Middleware.new(app, :subdomain).call(env)
      expect(status).to eq(200)
    end

    it "processes request successfully without tenant when not required" do
      env = Rack::MockRequest.env_for("http://example.com/")
      status, _headers, _body = BetterTenant::Middleware.new(app, :subdomain).call(env)
      expect(status).to eq(200)
    end
  end

  describe "error scenarios with audit enabled" do
    let(:config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme globex]
        c.persistent_schemas %w[shared]
        c.schema_format "tenant_%{tenant}"
        c.require_tenant true
        c.audit_violations true
      end
    end

    it "raises TenantNotFoundError for unknown tenant" do
      env = Rack::MockRequest.env_for("http://unknown.example.com/")

      expect {
        BetterTenant::Middleware.new(app, :subdomain).call(env)
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end

    it "raises TenantContextMissingError when no tenant detected" do
      env = Rack::MockRequest.env_for("http://example.com/")

      expect {
        BetterTenant::Middleware.new(app, :subdomain).call(env)
      }.to raise_error(BetterTenant::Errors::TenantContextMissingError)
    end
  end

  describe "combined audit settings" do
    let(:config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :column
        c.tenant_names %w[acme globex]
        c.audit_access true
        c.audit_violations true
        c.require_tenant false
      end
    end

    it "stores both audit settings correctly" do
      expect(BetterTenant::Tenant.configuration[:audit_access]).to be true
      expect(BetterTenant::Tenant.configuration[:audit_violations]).to be true
    end
  end
end
