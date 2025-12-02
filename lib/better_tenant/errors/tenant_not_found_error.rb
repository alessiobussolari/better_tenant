# frozen_string_literal: true

require_relative "tenant_error"

module BetterTenant
  module Errors
    # Raised when a tenant is not found.
    class TenantNotFoundError < TenantError
      attr_reader :tenant_name

      # @param tenant_name [String] The name of the tenant that was not found
      def initialize(tenant_name:)
        @tenant_name = tenant_name
        super("Tenant '#{tenant_name}' not found")
      end

      # Sentry-compatible tags
      # @return [Hash]
      def tags
        {
          error_category: "tenant_not_found",
          module: "better_tenant",
          tenant: tenant_name.to_s
        }
      end

      # Sentry-compatible context
      # @return [Hash]
      def context
        {}
      end

      # Sentry-compatible extra data
      # @return [Hash]
      def extra
        { tenant_name: tenant_name }
      end
    end
  end
end
