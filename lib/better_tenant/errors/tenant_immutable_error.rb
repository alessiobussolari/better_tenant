# frozen_string_literal: true

require_relative "tenant_error"

module BetterTenant
  module Errors
    # Raised when attempting to modify an immutable tenant column.
    class TenantImmutableError < TenantError
      attr_reader :tenant_column, :model_class, :record_id

      # @param tenant_column [Symbol] The tenant column name
      # @param model_class [String] The model class of the record
      # @param record_id [Integer, nil] The ID of the record
      def initialize(tenant_column:, model_class:, record_id: nil)
        @tenant_column = tenant_column
        @model_class = model_class
        @record_id = record_id
        super(build_message)
      end

      # Sentry-compatible tags
      # @return [Hash]
      def tags
        {
          error_category: "tenant_immutable",
          module: "better_tenant"
        }
      end

      # Sentry-compatible context
      # @return [Hash]
      def context
        ctx = { model_class: model_class }
        ctx[:record_id] = record_id if record_id
        ctx
      end

      # Sentry-compatible extra data
      # @return [Hash]
      def extra
        {
          tenant_column: tenant_column,
          model_class: model_class,
          record_id: record_id
        }
      end

      private

      def build_message
        "Cannot modify immutable tenant column '#{tenant_column}'"
      end
    end
  end
end
