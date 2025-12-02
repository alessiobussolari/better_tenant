# frozen_string_literal: true

module BetterTenant
  # Configurator for BetterTenant module settings.
  #
  # This configurator allows setting global multi-tenancy options
  # for the entire application.
  #
  # @example Basic configuration
  #   BetterTenant.configure do |config|
  #     config.strategy :schema
  #     config.tenant_names -> { Tenant.pluck(:name) }
  #     config.excluded_models %w[User Tenant]
  #   end
  #
  class Configurator
    VALID_STRATEGIES = %i[column schema].freeze
    VALID_ELEVATORS = %i[subdomain domain header generic host path].freeze

    def initialize
      @strategy = :column
      @tenant_column = :tenant_id
      @tenant_names = []
      @tenant_model = nil
      @tenant_identifier = :id
      @excluded_models = []
      @persistent_schemas = []
      @schema_format = "%{tenant}"
      @elevator = nil
      @excluded_subdomains = []
      @excluded_paths = []
      @audit_violations = false
      @audit_access = false
      @require_tenant = true
      @strict_mode = false
      @callbacks = {
        before_create: nil,
        after_create: nil,
        before_switch: nil,
        after_switch: nil
      }
    end

    # Set the isolation strategy
    # @param value [Symbol] :column or :schema
    # @return [void]
    def strategy(value)
      unless VALID_STRATEGIES.include?(value)
        raise Errors::ConfigurationError,
          "strategy must be one of #{VALID_STRATEGIES.inspect}, got #{value.inspect}"
      end
      @strategy = value
    end

    # Set the tenant column name (for column strategy)
    # @param value [Symbol, String] The column name
    # @return [void]
    def tenant_column(value)
      @tenant_column = value.to_sym
    end

    # Set the tenant names list or proc
    # @param value [Array, Proc] List of tenant names or proc that returns them
    # @return [void]
    def tenant_names(value)
      unless value.is_a?(Array) || value.respond_to?(:call)
        raise Errors::ConfigurationError,
          "tenant_names must be an Array or callable (Proc/Lambda), got #{value.class}"
      end
      @tenant_names = value
    end

    # Set the tenant model class name
    # This automatically:
    # - Creates a Proc for tenant_names that queries the model
    # - Adds the model to excluded_models
    #
    # @param value [String, Class] Model class name or class
    # @return [void]
    #
    # @example Using tenant_model
    #   config.tenant_model "Organization"
    #   config.tenant_identifier :slug  # defaults to :id
    #
    def tenant_model(value)
      @tenant_model = value.is_a?(String) ? value : value.name
    end

    # Set the tenant identifier column (used with tenant_model)
    # @param value [Symbol, String] The column to use as identifier
    # @return [void]
    def tenant_identifier(value)
      @tenant_identifier = value.to_sym
    end

    # Set the excluded models (remain in public schema)
    # @param value [Array<String>] Model class names to exclude
    # @return [void]
    def excluded_models(value)
      unless value.is_a?(Array)
        raise Errors::ConfigurationError,
          "excluded_models must be an array, got #{value.class}"
      end
      @excluded_models = value
    end

    # Set persistent schemas (always in search_path)
    # @param value [Array<String>] Schema names
    # @return [void]
    def persistent_schemas(value)
      unless value.is_a?(Array)
        raise Errors::ConfigurationError,
          "persistent_schemas must be an array, got #{value.class}"
      end
      @persistent_schemas = value
    end

    # Set the schema format template
    # @param value [String] Format string with %{tenant} placeholder
    # @return [void]
    def schema_format(value)
      unless value.is_a?(String)
        raise Errors::ConfigurationError,
          "schema_format must be a string, got #{value.class}"
      end
      @schema_format = value
    end

    # Set the elevator for tenant resolution from requests
    # @param value [Symbol, Proc] Elevator type or custom proc
    # @return [void]
    def elevator(value)
      if value.is_a?(Symbol)
        unless VALID_ELEVATORS.include?(value)
          raise Errors::ConfigurationError,
            "elevator must be one of #{VALID_ELEVATORS.inspect}, got #{value.inspect}"
        end
      elsif !value.respond_to?(:call)
        raise Errors::ConfigurationError,
          "elevator must be a symbol or callable, got #{value.class}"
      end
      @elevator = value
    end

    # Set excluded subdomains (for subdomain elevator)
    # @param value [Array<String>] Subdomains to exclude
    # @return [void]
    def excluded_subdomains(value)
      unless value.is_a?(Array)
        raise Errors::ConfigurationError,
          "excluded_subdomains must be an array, got #{value.class}"
      end
      @excluded_subdomains = value
    end

    # Set excluded paths (for path elevator)
    # @param value [Array<String>] Path segments to exclude
    # @return [void]
    def excluded_paths(value)
      unless value.is_a?(Array)
        raise Errors::ConfigurationError,
          "excluded_paths must be an array, got #{value.class}"
      end
      @excluded_paths = value
    end

    # Enable/disable audit logging for violations
    # @param value [Boolean] Enable audit violations
    # @return [void]
    def audit_violations(value)
      validate_boolean!(value, "audit_violations")
      @audit_violations = value
    end

    # Enable/disable audit logging for all access
    # @param value [Boolean] Enable audit access
    # @return [void]
    def audit_access(value)
      validate_boolean!(value, "audit_access")
      @audit_access = value
    end

    # Require tenant context for operations
    # @param value [Boolean] Require tenant
    # @return [void]
    def require_tenant(value)
      validate_boolean!(value, "require_tenant")
      @require_tenant = value
    end

    # Enable strict mode (post-query validation)
    # @param value [Boolean] Enable strict mode
    # @return [void]
    def strict_mode(value)
      validate_boolean!(value, "strict_mode")
      @strict_mode = value
    end

    # Register before_create callback
    # @yield [tenant_name] Block to execute before tenant creation
    # @return [void]
    def before_create(&block)
      raise Errors::ConfigurationError, "before_create requires a block" unless block_given?
      @callbacks[:before_create] = block
    end

    # Register after_create callback
    # @yield [tenant_name] Block to execute after tenant creation
    # @return [void]
    def after_create(&block)
      raise Errors::ConfigurationError, "after_create requires a block" unless block_given?
      @callbacks[:after_create] = block
    end

    # Register before_switch callback
    # @yield [from_tenant, to_tenant] Block to execute before tenant switch
    # @return [void]
    def before_switch(&block)
      raise Errors::ConfigurationError, "before_switch requires a block" unless block_given?
      @callbacks[:before_switch] = block
    end

    # Register after_switch callback
    # @yield [from_tenant, to_tenant] Block to execute after tenant switch
    # @return [void]
    def after_switch(&block)
      raise Errors::ConfigurationError, "after_switch requires a block" unless block_given?
      @callbacks[:after_switch] = block
    end

    # Validate the configuration
    # @return [void]
    # @raise [ConfigurationError] If configuration is invalid
    def validate!
      # Add any cross-field validation here
      true
    end

    # Return configuration as a hash
    # @return [Hash] The configuration hash
    def to_h
      # Process tenant_model if set
      tenant_names_value = resolve_tenant_names
      excluded_models_value = resolve_excluded_models

      {
        strategy: @strategy,
        tenant_column: @tenant_column,
        tenant_names: tenant_names_value,
        tenant_model: @tenant_model,
        tenant_identifier: @tenant_identifier,
        excluded_models: excluded_models_value,
        persistent_schemas: @persistent_schemas,
        schema_format: @schema_format,
        elevator: @elevator,
        excluded_subdomains: @excluded_subdomains,
        excluded_paths: @excluded_paths,
        audit_violations: @audit_violations,
        audit_access: @audit_access,
        require_tenant: @require_tenant,
        strict_mode: @strict_mode,
        callbacks: @callbacks
      }
    end

    private

    def validate_boolean!(value, name)
      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        raise Errors::ConfigurationError,
          "#{name} must be a boolean, got #{value.class}"
      end
    end

    # Resolve tenant_names - if tenant_model is set, create a Proc
    # @return [Array, Proc] The tenant names or a Proc to fetch them
    def resolve_tenant_names
      return @tenant_names unless @tenant_model && @tenant_names.empty?
      return @tenant_names if @tenant_model.nil?

      # Create a Proc that queries the model for tenant identifiers
      model_name = @tenant_model
      identifier = @tenant_identifier

      -> { model_name.constantize.pluck(identifier).map(&:to_s) }
    end

    # Resolve excluded_models - auto-add tenant_model if set
    # @return [Array<String>] The excluded model names
    def resolve_excluded_models
      return @excluded_models unless @tenant_model

      # Add tenant_model to excluded_models if not already present
      if @excluded_models.include?(@tenant_model)
        @excluded_models
      else
        @excluded_models + [@tenant_model]
      end
    end
  end
end
