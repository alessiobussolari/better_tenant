# frozen_string_literal: true

require_relative "tenant_error"

module BetterTenant
  module Errors
    # Raised when a PostgreSQL schema for a tenant is not found.
    class SchemaNotFoundError < TenantError
      attr_reader :schema_name, :tenant_name

      # @param schema_name [String] The name of the schema that was not found
      # @param tenant_name [String, nil] The tenant name associated with the schema
      def initialize(schema_name:, tenant_name: nil)
        @schema_name = schema_name
        @tenant_name = tenant_name
        super(build_message)
      end

      # Sentry-compatible tags
      # @return [Hash]
      def tags
        tags = {
          error_category: "schema_not_found",
          module: "better_tenant"
        }
        tags[:tenant] = tenant_name if tenant_name
        tags
      end

      # Sentry-compatible context
      # @return [Hash]
      def context
        {}
      end

      # Sentry-compatible extra data
      # @return [Hash]
      def extra
        {
          schema_name: schema_name,
          tenant_name: tenant_name
        }
      end

      private

      def build_message
        "PostgreSQL schema '#{schema_name}' not found"
      end
    end
  end
end
