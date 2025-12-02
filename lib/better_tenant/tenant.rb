# frozen_string_literal: true

module BetterTenant
  # Tenant facade for multi-tenancy operations.
  #
  # This class provides a simple, thread-safe API for managing tenants,
  # inspired by the Apartment gem's API.
  #
  # @example Basic usage
  #   BetterTenant::Tenant.switch("acme") do
  #     Article.all  # Scoped to acme tenant
  #   end
  #
  # @example Permanent switch
  #   BetterTenant::Tenant.switch!("acme")
  #   Article.all  # Scoped to acme tenant
  #
  # @example Creating a tenant
  #   BetterTenant::Tenant.create("new_tenant")
  #
  class Tenant
    class << self
      # Configure the tenant system
      # @param configurator [BetterTenant::Configurator] The configurator instance
      def configure(configurator)
        @configuration = configurator.to_h
        @adapter = build_adapter(@configuration)
      end

      # Get the current configuration
      # @return [Hash] The configuration hash
      def configuration
        ensure_configured!
        @configuration
      end

      # Get the current tenant
      # @return [String, nil] The current tenant name or nil
      def current
        ensure_configured!
        @adapter.current
      end

      # Switch to a tenant permanently
      # @param tenant [String] The tenant name
      # @return [String] The tenant name
      def switch!(tenant)
        ensure_configured!
        @adapter.switch!(tenant)
      end

      # Switch to a tenant for the duration of a block
      # @param tenant [String] The tenant name
      # @yield Block to execute in tenant context
      # @return [Object] The block's return value
      def switch(tenant, &block)
        ensure_configured!
        @adapter.switch(tenant, &block)
      end

      # Reset to the default tenant (public schema)
      def reset
        ensure_configured!
        @adapter.reset
      end

      # Create a new tenant
      # @param tenant [String] The tenant name
      def create(tenant)
        ensure_configured!
        @adapter.create(tenant)
      end

      # Drop a tenant
      # @param tenant [String] The tenant name
      def drop(tenant)
        ensure_configured!
        @adapter.drop(tenant)
      end

      # Check if a tenant exists
      # @param tenant [String] The tenant name
      # @return [Boolean]
      def exists?(tenant)
        ensure_configured!
        @adapter.exists?(tenant)
      end

      # Get all tenant names
      # @return [Array<String>]
      def tenant_names
        ensure_configured!
        @adapter.all_tenants
      end

      # Iterate over all tenants
      # @yield [tenant] Block to execute for each tenant
      def each(&block)
        ensure_configured!
        @adapter.each_tenant(&block)
      end

      # Get the adapter instance
      # @return [BetterTenant::Adapters::AbstractAdapter]
      def adapter
        ensure_configured!
        @adapter
      end

      # Check if a model is excluded from tenancy
      # @param model_name [String] The model class name
      # @return [Boolean]
      def excluded_model?(model_name)
        ensure_configured!
        excluded = @configuration[:excluded_models] || []
        excluded.include?(model_name)
      end

      # Reset the singleton state (for testing)
      def reset!
        @configuration = nil
        @adapter = nil
      end

      private

      def ensure_configured!
        return if @configuration && @adapter

        raise Errors::ConfigurationError,
          "BetterTenant::Tenant is not configured. " \
          "Call BetterTenant::Tenant.configure with a Configurator instance."
      end

      def build_adapter(config)
        case config[:strategy]
        when :schema
          Adapters::PostgresqlAdapter.new(config)
        when :column
          Adapters::ColumnAdapter.new(config)
        else
          raise Errors::ConfigurationError,
            "Unknown strategy: #{config[:strategy]}"
        end
      end
    end
  end
end
