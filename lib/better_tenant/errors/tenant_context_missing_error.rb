# frozen_string_literal: true

require_relative "tenant_error"

module BetterTenant
  module Errors
    # Raised when a tenant context is required but not set.
    class TenantContextMissingError < TenantError
      attr_reader :operation, :model_class

      # @param operation [Symbol] The operation that requires a tenant context
      # @param model_class [String, nil] The model class attempting the operation
      def initialize(operation: :unknown, model_class: nil)
        @operation = operation
        @model_class = model_class
        super(build_message)
      end

      # Sentry-compatible tags
      # @return [Hash]
      def tags
        {
          error_category: "tenant_context_missing",
          module: "better_tenant",
          operation: operation.to_s
        }
      end

      # Sentry-compatible context
      # @return [Hash]
      def context
        ctx = {}
        ctx[:model_class] = model_class if model_class
        ctx
      end

      # Sentry-compatible extra data
      # @return [Hash]
      def extra
        {
          operation: operation,
          model_class: model_class
        }
      end

      private

      def build_message
        msg = "No tenant context set for #{operation} operation"
        msg += " on #{model_class}" if model_class
        msg
      end
    end
  end
end
