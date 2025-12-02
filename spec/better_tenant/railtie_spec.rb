# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant Railtie Integration" do
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

  describe "configuration DSL" do
    it "allows configuring through BetterTenant.configure" do
      BetterTenant.configure do |t|
        t.strategy :schema
        t.tenant_names %w[acme globex]
        t.excluded_models %w[User]
        t.persistent_schemas %w[shared]
      end

      expect(BetterTenant::Tenant.configuration[:strategy]).to eq(:schema)
      expect(BetterTenant::Tenant.configuration[:tenant_names]).to eq(%w[acme globex])
      expect(BetterTenant::Tenant.configuration[:excluded_models]).to eq(%w[User])
    end

    it "supports column strategy configuration" do
      BetterTenant.configure do |t|
        t.strategy :column
        t.tenant_column :organization_id
        t.tenant_names -> { %w[org1 org2] }
      end

      expect(BetterTenant::Tenant.configuration[:strategy]).to eq(:column)
      expect(BetterTenant::Tenant.configuration[:tenant_column]).to eq(:organization_id)
    end

    it "supports callbacks configuration" do
      callback_called = false

      BetterTenant.configure do |t|
        t.strategy :column
        t.tenant_names %w[acme]
        t.after_switch { |_from, _to| callback_called = true }
      end

      BetterTenant::Tenant.switch!("acme")
      expect(callback_called).to be true
    end
  end

  describe "middleware auto-insertion" do
    it "provides middleware class for manual insertion" do
      expect(BetterTenant::Middleware).to be_a(Class)
    end

    it "middleware can be configured with different elevators" do
      expect {
        BetterTenant::Middleware.new(->(_) { [200, {}, ""] }, :subdomain)
      }.not_to raise_error

      expect {
        BetterTenant::Middleware.new(->(_) { [200, {}, ""] }, :header)
      }.not_to raise_error

      expect {
        BetterTenant::Middleware.new(->(_) { [200, {}, ""] }, ->(req) { req.host })
      }.not_to raise_error
    end
  end

  describe "ActiveRecord extension loading" do
    it "provides ActiveRecordExtension module" do
      expect(BetterTenant::ActiveRecordExtension).to be_a(Module)
    end

    it "can be included in models" do
      BetterTenant.configure do |t|
        t.strategy :column
        t.tenant_names %w[test]
        t.require_tenant false
      end

      model_class = Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include BetterTenant::ActiveRecordExtension
      end

      expect(model_class.tenantable?).to be true
    end
  end

  describe "elevator configuration" do
    it "supports all elevator types in configuration" do
      [:subdomain, :domain, :header, :path, :generic].each do |elevator_type|
        BetterTenant.configure do |t|
          t.strategy :column
          t.tenant_names %w[test]
          t.elevator elevator_type
        end

        expect(BetterTenant::Tenant.configuration[:elevator]).to eq(elevator_type)
      end
    end

    it "supports proc elevator in configuration" do
      custom_elevator = ->(request) { request.params["tenant"] }

      BetterTenant.configure do |t|
        t.strategy :column
        t.tenant_names %w[test]
        t.elevator custom_elevator
      end

      expect(BetterTenant::Tenant.configuration[:elevator]).to eq(custom_elevator)
    end
  end

  describe "default configuration values" do
    before { BetterTenant::Tenant.reset! }

    it "provides sensible defaults" do
      BetterTenant.configure do |t|
        t.strategy :column
        t.tenant_names %w[test]
      end

      config = BetterTenant::Tenant.configuration
      expect(config[:tenant_column]).to eq(:tenant_id)
      expect(config[:excluded_models]).to eq([])
      expect(config[:require_tenant]).to be true  # Default is true
      expect(config[:strict_mode]).to be false
      expect(config[:audit_violations]).to be false
      expect(config[:audit_access]).to be false
    end

    it "allows overriding all defaults" do
      BetterTenant.configure do |t|
        t.strategy :column
        t.tenant_names %w[test]
        t.tenant_column :organization_id
        t.excluded_models %w[User Admin]
        t.require_tenant true
        t.strict_mode true
        t.audit_violations true
        t.audit_access true
      end

      config = BetterTenant::Tenant.configuration
      expect(config[:tenant_column]).to eq(:organization_id)
      expect(config[:excluded_models]).to eq(%w[User Admin])
      expect(config[:require_tenant]).to be true
      expect(config[:strict_mode]).to be true
      expect(config[:audit_violations]).to be true
      expect(config[:audit_access]).to be true
    end
  end

  describe "full configuration with all options" do
    it "accepts a complete configuration" do
      BetterTenant.configure do |t|
        t.strategy :schema
        t.tenant_names %w[acme globex]
        t.excluded_models %w[User Tenant]
        t.persistent_schemas %w[shared extensions]
        t.schema_format "tenant_%{tenant}"
        t.elevator :subdomain
        t.excluded_subdomains %w[www admin api]
        t.excluded_paths %w[health webhooks]
        t.require_tenant true
        t.strict_mode true
        t.audit_violations true
        t.audit_access true
        t.before_switch { |from, to| puts "Switching from #{from} to #{to}" }
        t.after_switch { |from, to| puts "Switched from #{from} to #{to}" }
      end

      config = BetterTenant::Tenant.configuration
      expect(config[:strategy]).to eq(:schema)
      expect(config[:tenant_names]).to eq(%w[acme globex])
      expect(config[:excluded_models]).to eq(%w[User Tenant])
      expect(config[:persistent_schemas]).to eq(%w[shared extensions])
      expect(config[:schema_format]).to eq("tenant_%{tenant}")
      expect(config[:elevator]).to eq(:subdomain)
      expect(config[:excluded_subdomains]).to eq(%w[www admin api])
      expect(config[:excluded_paths]).to eq(%w[health webhooks])
      expect(config[:require_tenant]).to be true
      expect(config[:strict_mode]).to be true
      expect(config[:audit_violations]).to be true
      expect(config[:audit_access]).to be true
      expect(config[:callbacks][:before_switch]).to be_a(Proc)
      expect(config[:callbacks][:after_switch]).to be_a(Proc)
    end
  end
end
