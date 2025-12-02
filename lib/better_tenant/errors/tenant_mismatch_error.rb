# frozen_string_literal: true

require_relative "tenant_error"

module BetterTenant
  module Errors
    # Raised when a record belongs to a different tenant than expected.
    class TenantMismatchError < TenantError
      attr_reader :expected_tenant_id, :actual_tenant_id, :operation, :model_class

      # @param expected_tenant_id [String] The expected tenant ID
      # @param actual_tenant_id [String] The actual tenant ID on the record
      # @param operation [Symbol] The operation being performed
      # @param model_class [String] The model class of the record
      def initialize(expected_tenant_id:, actual_tenant_id:, operation:, model_class:)
        @expected_tenant_id = expected_tenant_id
        @actual_tenant_id = actual_tenant_id
        @operation = operation
        @model_class = model_class
        super(build_message)
      end

      # Sentry-compatible tags
      # @return [Hash]
      def tags
        {
          error_category: "tenant_mismatch",
          module: "better_tenant",
          operation: operation.to_s
        }
      end

      # Sentry-compatible context
      # @return [Hash]
      def context
        { model_class: model_class }
      end

      # Sentry-compatible extra data
      # @return [Hash]
      def extra
        {
          expected_tenant_id: expected_tenant_id,
          actual_tenant_id: actual_tenant_id,
          operation: operation
        }
      end

      private

      def build_message
        "Tenant mismatch: expected '#{expected_tenant_id}', " \
          "got '#{actual_tenant_id}' during #{operation}"
      end
    end
  end
end
