# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Configurator do
  subject(:configurator) { described_class.new }

  describe "initialization" do
    it "initializes with default values" do
      expect(configurator.to_h[:strategy]).to eq(:column)
    end

    it "has no excluded_models by default" do
      expect(configurator.to_h[:excluded_models]).to eq([])
    end

    it "has no persistent_schemas by default" do
      expect(configurator.to_h[:persistent_schemas]).to eq([])
    end

    it "has tenant_id as default tenant_column" do
      expect(configurator.to_h[:tenant_column]).to eq(:tenant_id)
    end
  end

  describe "#strategy" do
    it "accepts :column strategy" do
      configurator.strategy(:column)
      expect(configurator.to_h[:strategy]).to eq(:column)
    end

    it "accepts :schema strategy" do
      configurator.strategy(:schema)
      expect(configurator.to_h[:strategy]).to eq(:schema)
    end

    it "raises ConfigurationError for invalid strategy" do
      expect {
        configurator.strategy(:invalid)
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be one of/)
    end
  end

  describe "#tenant_column" do
    it "sets the tenant column" do
      configurator.tenant_column(:organization_id)
      expect(configurator.to_h[:tenant_column]).to eq(:organization_id)
    end

    it "converts string to symbol" do
      configurator.tenant_column("company_id")
      expect(configurator.to_h[:tenant_column]).to eq(:company_id)
    end
  end

  describe "#tenant_names" do
    it "accepts an array of tenant names" do
      configurator.tenant_names(%w[acme globex initech])
      expect(configurator.to_h[:tenant_names]).to eq(%w[acme globex initech])
    end

    it "accepts a proc/lambda" do
      tenant_proc = -> { %w[acme globex] }
      configurator.tenant_names(tenant_proc)
      expect(configurator.to_h[:tenant_names]).to eq(tenant_proc)
    end

    it "raises ConfigurationError for invalid type" do
      expect {
        configurator.tenant_names("not_valid")
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be an Array or callable/)
    end
  end

  describe "#excluded_models" do
    it "sets excluded models" do
      configurator.excluded_models(%w[User Tenant])
      expect(configurator.to_h[:excluded_models]).to eq(%w[User Tenant])
    end

    it "raises ConfigurationError for non-array" do
      expect {
        configurator.excluded_models("User")
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be an array/)
    end
  end

  describe "#persistent_schemas" do
    it "sets persistent schemas" do
      configurator.persistent_schemas(%w[shared extensions])
      expect(configurator.to_h[:persistent_schemas]).to eq(%w[shared extensions])
    end

    it "raises ConfigurationError for non-array" do
      expect {
        configurator.persistent_schemas("shared")
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be an array/)
    end
  end

  describe "#schema_format" do
    it "sets the schema format template" do
      configurator.schema_format("tenant_%{tenant}")
      expect(configurator.to_h[:schema_format]).to eq("tenant_%{tenant}")
    end

    it "raises ConfigurationError for non-string" do
      expect {
        configurator.schema_format(:invalid)
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be a string/)
    end
  end

  describe "#elevator" do
    it "accepts :subdomain symbol" do
      configurator.elevator(:subdomain)
      expect(configurator.to_h[:elevator]).to eq(:subdomain)
    end

    it "accepts :domain symbol" do
      configurator.elevator(:domain)
      expect(configurator.to_h[:elevator]).to eq(:domain)
    end

    it "accepts :header symbol" do
      configurator.elevator(:header)
      expect(configurator.to_h[:elevator]).to eq(:header)
    end

    it "accepts :generic symbol" do
      configurator.elevator(:generic)
      expect(configurator.to_h[:elevator]).to eq(:generic)
    end

    it "accepts a proc/lambda" do
      resolver = ->(request) { request.headers["X-Tenant"] }
      configurator.elevator(resolver)
      expect(configurator.to_h[:elevator]).to eq(resolver)
    end

    it "raises ConfigurationError for invalid symbol" do
      expect {
        configurator.elevator(:invalid_elevator)
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be one of/)
    end
  end

  describe "#excluded_subdomains" do
    it "sets excluded subdomains" do
      configurator.excluded_subdomains(%w[www admin api])
      expect(configurator.to_h[:excluded_subdomains]).to eq(%w[www admin api])
    end

    it "raises ConfigurationError for non-array" do
      expect {
        configurator.excluded_subdomains("www")
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be an array/)
    end
  end

  describe "#audit_violations" do
    it "enables audit violations" do
      configurator.audit_violations(true)
      expect(configurator.to_h[:audit_violations]).to be true
    end

    it "disables audit violations" do
      configurator.audit_violations(false)
      expect(configurator.to_h[:audit_violations]).to be false
    end

    it "raises ConfigurationError for non-boolean" do
      expect {
        configurator.audit_violations("yes")
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be a boolean/)
    end
  end

  describe "#audit_access" do
    it "enables audit access" do
      configurator.audit_access(true)
      expect(configurator.to_h[:audit_access]).to be true
    end

    it "disables audit access" do
      configurator.audit_access(false)
      expect(configurator.to_h[:audit_access]).to be false
    end
  end

  describe "#require_tenant" do
    it "enables require_tenant" do
      configurator.require_tenant(true)
      expect(configurator.to_h[:require_tenant]).to be true
    end

    it "disables require_tenant" do
      configurator.require_tenant(false)
      expect(configurator.to_h[:require_tenant]).to be false
    end
  end

  describe "#strict_mode" do
    it "enables strict_mode" do
      configurator.strict_mode(true)
      expect(configurator.to_h[:strict_mode]).to be true
    end

    it "disables strict_mode" do
      configurator.strict_mode(false)
      expect(configurator.to_h[:strict_mode]).to be false
    end
  end

  describe "callbacks" do
    describe "#before_create" do
      it "registers a before_create callback" do
        callback = proc { |tenant| puts tenant }
        configurator.before_create(&callback)
        expect(configurator.to_h[:callbacks][:before_create]).to eq(callback)
      end

      it "raises ConfigurationError without block" do
        expect {
          configurator.before_create
        }.to raise_error(BetterTenant::Errors::ConfigurationError, /requires a block/)
      end
    end

    describe "#after_create" do
      it "registers an after_create callback" do
        callback = proc { |tenant| puts tenant }
        configurator.after_create(&callback)
        expect(configurator.to_h[:callbacks][:after_create]).to eq(callback)
      end
    end

    describe "#before_switch" do
      it "registers a before_switch callback" do
        callback = proc { |from, to| puts "#{from} -> #{to}" }
        configurator.before_switch(&callback)
        expect(configurator.to_h[:callbacks][:before_switch]).to eq(callback)
      end
    end

    describe "#after_switch" do
      it "registers an after_switch callback" do
        callback = proc { |from, to| puts "switched" }
        configurator.after_switch(&callback)
        expect(configurator.to_h[:callbacks][:after_switch]).to eq(callback)
      end
    end
  end

  describe "#to_h" do
    it "returns all configuration as a hash" do
      configurator.strategy(:schema)
      configurator.tenant_column(:org_id)
      configurator.excluded_models(%w[User])
      configurator.audit_violations(true)

      config = configurator.to_h

      expect(config[:strategy]).to eq(:schema)
      expect(config[:tenant_column]).to eq(:org_id)
      expect(config[:excluded_models]).to eq(%w[User])
      expect(config[:audit_violations]).to be true
    end
  end

  describe "#validate!" do
    context "with :schema strategy" do
      before { configurator.strategy(:schema) }

      it "passes validation with valid config" do
        configurator.tenant_names(%w[acme])
        expect { configurator.validate! }.not_to raise_error
      end
    end

    context "with :column strategy" do
      before { configurator.strategy(:column) }

      it "passes validation with valid config" do
        configurator.tenant_column(:tenant_id)
        expect { configurator.validate! }.not_to raise_error
      end
    end

    context "cross-field validation" do
      it "passes validation with empty tenant_names for schema strategy" do
        configurator.strategy(:schema)
        configurator.tenant_names([])
        expect { configurator.validate! }.not_to raise_error
      end

      it "uses default tenant_column for column strategy" do
        configurator.strategy(:column)
        expect { configurator.validate! }.not_to raise_error
        expect(configurator.to_h[:tenant_column]).to eq(:tenant_id)
      end

      it "accepts schema_format without placeholder" do
        configurator.strategy(:schema)
        configurator.tenant_names(%w[acme])
        configurator.schema_format("static_schema")
        expect { configurator.validate! }.not_to raise_error
      end

      it "accepts schema_format with placeholder" do
        configurator.strategy(:schema)
        configurator.tenant_names(%w[acme])
        configurator.schema_format("tenant_%{tenant}")
        expect { configurator.validate! }.not_to raise_error
      end

      it "validates all boolean settings" do
        configurator.strategy(:column)
        configurator.tenant_names(%w[acme])
        configurator.require_tenant(true)
        configurator.strict_mode(true)
        configurator.audit_violations(true)
        configurator.audit_access(true)
        expect { configurator.validate! }.not_to raise_error
      end
    end
  end

  describe "#excluded_paths" do
    it "sets excluded paths" do
      configurator.excluded_paths(%w[api health webhooks])
      expect(configurator.to_h[:excluded_paths]).to eq(%w[api health webhooks])
    end

    it "raises ConfigurationError for non-array" do
      expect {
        configurator.excluded_paths("api")
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be an array/)
    end
  end

  describe "#require_tenant" do
    it "raises ConfigurationError for non-boolean" do
      expect {
        configurator.require_tenant("yes")
      }.to raise_error(BetterTenant::Errors::ConfigurationError, /must be a boolean/)
    end
  end

  describe "edge cases" do
    describe "tenant_names with various callables" do
      it "accepts a Method object" do
        def self.fetch_tenants
          %w[tenant1 tenant2]
        end
        configurator.tenant_names(method(:fetch_tenants))
        expect(configurator.to_h[:tenant_names].call).to eq(%w[tenant1 tenant2])
      end

      it "accepts a custom callable object" do
        callable = Class.new do
          def call
            %w[custom1 custom2]
          end
        end.new
        configurator.tenant_names(callable)
        expect(configurator.to_h[:tenant_names].call).to eq(%w[custom1 custom2])
      end

      it "accepts an empty array" do
        configurator.tenant_names([])
        expect(configurator.to_h[:tenant_names]).to eq([])
      end

      it "accepts array with special characters in names" do
        configurator.tenant_names(%w[tenant-1 tenant_2 tenant.3])
        expect(configurator.to_h[:tenant_names]).to eq(%w[tenant-1 tenant_2 tenant.3])
      end
    end

    describe "excluded_models edge cases" do
      it "accepts empty array" do
        configurator.excluded_models([])
        expect(configurator.to_h[:excluded_models]).to eq([])
      end

      it "does not deduplicate entries" do
        configurator.excluded_models(%w[User User Admin])
        expect(configurator.to_h[:excluded_models]).to eq(%w[User User Admin])
      end
    end

    describe "schema_format edge cases" do
      it "accepts empty string" do
        configurator.schema_format("")
        expect(configurator.to_h[:schema_format]).to eq("")
      end

      it "accepts format with multiple placeholders" do
        configurator.schema_format("%{tenant}_%{tenant}")
        expect(configurator.to_h[:schema_format]).to eq("%{tenant}_%{tenant}")
      end

      it "accepts format without any placeholder" do
        configurator.schema_format("static_schema")
        expect(configurator.to_h[:schema_format]).to eq("static_schema")
      end
    end

    describe "elevator edge cases" do
      it "accepts :host elevator" do
        configurator.elevator(:host)
        expect(configurator.to_h[:elevator]).to eq(:host)
      end

      it "accepts :path elevator" do
        configurator.elevator(:path)
        expect(configurator.to_h[:elevator]).to eq(:path)
      end

      it "accepts lambda with zero arguments" do
        resolver = -> { "default_tenant" }
        configurator.elevator(resolver)
        expect(configurator.to_h[:elevator]).to eq(resolver)
      end
    end

    describe "callback edge cases" do
      it "overwrites existing callback" do
        first_callback = proc { "first" }
        second_callback = proc { "second" }

        configurator.before_create(&first_callback)
        configurator.before_create(&second_callback)

        expect(configurator.to_h[:callbacks][:before_create]).to eq(second_callback)
      end

      it "allows nil-returning callbacks" do
        callback = proc { nil }
        configurator.after_create(&callback)
        expect(configurator.to_h[:callbacks][:after_create].call).to be_nil
      end
    end

    describe "boolean validation edge cases" do
      it "rejects truthy non-boolean for require_tenant" do
        expect {
          configurator.require_tenant(1)
        }.to raise_error(BetterTenant::Errors::ConfigurationError)
      end

      it "rejects falsy non-boolean for require_tenant" do
        expect {
          configurator.require_tenant(0)
        }.to raise_error(BetterTenant::Errors::ConfigurationError)
      end

      it "rejects nil for strict_mode" do
        expect {
          configurator.strict_mode(nil)
        }.to raise_error(BetterTenant::Errors::ConfigurationError)
      end

      it "rejects nil for audit_violations" do
        expect {
          configurator.audit_violations(nil)
        }.to raise_error(BetterTenant::Errors::ConfigurationError)
      end

      it "rejects nil for audit_access" do
        expect {
          configurator.audit_access(nil)
        }.to raise_error(BetterTenant::Errors::ConfigurationError)
      end
    end

    describe "chained configuration" do
      it "supports method chaining style configuration" do
        configurator.strategy(:schema)
        configurator.tenant_names(%w[acme])
        configurator.excluded_models(%w[User])
        configurator.persistent_schemas(%w[shared])
        configurator.schema_format("tenant_%{tenant}")
        configurator.require_tenant(true)

        config = configurator.to_h
        expect(config[:strategy]).to eq(:schema)
        expect(config[:tenant_names]).to eq(%w[acme])
        expect(config[:excluded_models]).to eq(%w[User])
        expect(config[:persistent_schemas]).to eq(%w[shared])
        expect(config[:schema_format]).to eq("tenant_%{tenant}")
        expect(config[:require_tenant]).to be true
      end
    end

    describe "configuration hash completeness" do
      it "includes all expected keys" do
        config = configurator.to_h
        expected_keys = %i[
          strategy tenant_column tenant_names tenant_model tenant_identifier
          excluded_models persistent_schemas schema_format elevator
          excluded_subdomains excluded_paths audit_violations audit_access
          require_tenant strict_mode callbacks
        ]
        expected_keys.each do |key|
          expect(config).to have_key(key)
        end
      end

      it "has correct default values" do
        config = configurator.to_h
        expect(config[:strategy]).to eq(:column)
        expect(config[:tenant_column]).to eq(:tenant_id)
        expect(config[:tenant_names]).to eq([])
        expect(config[:tenant_model]).to be_nil
        expect(config[:tenant_identifier]).to eq(:id)
        expect(config[:excluded_models]).to eq([])
        expect(config[:persistent_schemas]).to eq([])
        expect(config[:schema_format]).to eq("%{tenant}")
        expect(config[:elevator]).to be_nil
        expect(config[:excluded_subdomains]).to eq([])
        expect(config[:excluded_paths]).to eq([])
        expect(config[:audit_violations]).to be false
        expect(config[:audit_access]).to be false
        expect(config[:require_tenant]).to be true
        expect(config[:strict_mode]).to be false
        expect(config[:callbacks]).to be_a(Hash)
      end
    end

    describe "error message quality" do
      it "includes valid options in strategy error" do
        expect {
          configurator.strategy(:invalid)
        }.to raise_error(BetterTenant::Errors::ConfigurationError, /\[:column, :schema\]/)
      end

      it "includes valid options in elevator error" do
        expect {
          configurator.elevator(:invalid)
        }.to raise_error(BetterTenant::Errors::ConfigurationError, /subdomain.*domain.*header/)
      end

      it "includes actual type in type mismatch errors" do
        expect {
          configurator.excluded_models("not_array")
        }.to raise_error(BetterTenant::Errors::ConfigurationError, /String/)
      end
    end
  end
end
