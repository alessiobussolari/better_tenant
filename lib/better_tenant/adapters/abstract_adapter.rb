# frozen_string_literal: true

module BetterTenant
  module Adapters
    # Abstract base adapter for tenant switching.
    #
    # Subclasses must implement:
    # - #switch!(tenant) - Switch to tenant permanently
    # - #reset - Reset to default tenant
    # - #create(tenant) - Create tenant schema/data
    # - #drop(tenant) - Drop tenant schema/data
    # - #exists?(tenant) - Check if tenant exists
    #
    class AbstractAdapter
      attr_reader :config, :current

      # @param config [Hash] The tenantable configuration
      def initialize(config)
        @config = config
        @current = nil
      end

      # Switch to a tenant permanently
      # @param tenant [String] The tenant name
      # @raise [NotImplementedError] Must be implemented by subclass
      def switch!(tenant)
        raise NotImplementedError, "#{self.class} must implement #switch!"
      end

      # Switch to a tenant for the duration of a block
      # @param tenant [String] The tenant name
      # @yield Block to execute in tenant context
      # @return [Object] The block's return value
      # @raise [NotImplementedError] Must be implemented by subclass
      def switch(tenant)
        raise NotImplementedError, "#{self.class} must implement #switch"
      end

      # Reset to the default tenant (public schema)
      # @raise [NotImplementedError] Must be implemented by subclass
      def reset
        raise NotImplementedError, "#{self.class} must implement #reset"
      end

      # Create a new tenant
      # @param tenant [String] The tenant name
      # @raise [NotImplementedError] Must be implemented by subclass
      def create(tenant)
        raise NotImplementedError, "#{self.class} must implement #create"
      end

      # Drop a tenant
      # @param tenant [String] The tenant name
      # @raise [NotImplementedError] Must be implemented by subclass
      def drop(tenant)
        raise NotImplementedError, "#{self.class} must implement #drop"
      end

      # Check if a tenant exists
      # @param tenant [String] The tenant name
      # @return [Boolean]
      # @raise [NotImplementedError] Must be implemented by subclass
      def exists?(tenant)
        raise NotImplementedError, "#{self.class} must implement #exists?"
      end

      # Get all tenant names
      # @return [Array<String>]
      def all_tenants
        tenant_names = config[:tenant_names]
        tenant_names.respond_to?(:call) ? tenant_names.call : tenant_names
      end

      # Get the schema name for a tenant
      # @param tenant [String] The tenant name
      # @return [String] The schema name
      def schema_for(tenant)
        format = config[:schema_format] || "%{tenant}"
        format % { tenant: tenant }
      end

      # Validate that a tenant exists
      # @param tenant [String] The tenant name to validate
      # @raise [TenantNotFoundError] If tenant doesn't exist
      def validate_tenant!(tenant)
        return if all_tenants.include?(tenant)

        raise Errors::TenantNotFoundError.new(tenant_name: tenant)
      end

      protected

      # Execute callbacks
      # @param name [Symbol] The callback name
      # @param args [Array] Arguments to pass to the callback
      def run_callback(name, *args)
        callback = config.dig(:callbacks, name)
        callback&.call(*args)
      end
    end
  end
end
