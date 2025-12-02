# frozen_string_literal: true

module BetterTenant
  # ActiveRecord extension for automatic tenant scoping.
  #
  # When included in a model, this module:
  # - Adds a default scope that filters by tenant_id
  # - Automatically sets tenant_id on new records
  # - Prevents changing tenant_id (in strict mode)
  # - Provides cross-tenant protection
  #
  # @example
  #   class Article < ApplicationRecord
  #     include BetterTenant::ActiveRecordExtension
  #   end
  #
  #   BetterTenant::Tenant.switch("acme") do
  #     Article.all  # WHERE tenant_id = 'acme'
  #   end
  #
  module ActiveRecordExtension
    extend ActiveSupport::Concern

    included do
      # Add default scope for tenant filtering (column strategy only)
      default_scope do
        klass = respond_to?(:klass) ? self.klass : self

        # Skip tenancy for excluded models
        if klass.excluded_from_tenancy?
          all
        elsif klass.column_strategy? && klass.current_tenant.present?
          where(klass.tenant_column => klass.current_tenant)
        elsif klass.column_strategy? && klass.require_tenant? && !klass.unscoped_tenant_context?
          raise Errors::TenantContextMissingError.new(
            operation: "query",
            model_class: klass.name
          )
        else
          all
        end
      end

      # Automatically set tenant_id before validation
      before_validation :set_tenant_id, on: :create

      # Validate tenant immutability in strict mode
      before_validation :validate_tenant_immutability, on: :update
    end

    class_methods do
      # Check if this model is tenantable
      # @return [Boolean]
      def tenantable?
        true
      end

      # Check if this model is excluded from tenancy
      # @return [Boolean]
      def excluded_from_tenancy?
        Tenant.excluded_model?(name)
      end

      # Get the tenant column name
      # @return [Symbol]
      def tenant_column
        Tenant.configuration[:tenant_column]
      end

      # Get the current tenant
      # @return [String, nil]
      def current_tenant
        return nil if Thread.current[:unscoped_tenant]

        Tenant.current
      end

      # Execute block without tenant scope
      # @yield Block to execute without tenant scope
      # @return [Object] Block result
      def unscoped_tenant
        previous_tenant = Tenant.current
        begin
          Thread.current[:unscoped_tenant] = true
          Tenant.reset if previous_tenant
          yield
        ensure
          Thread.current[:unscoped_tenant] = false
          Tenant.switch!(previous_tenant) if previous_tenant
        end
      end

      # Check if using column strategy
      # @return [Boolean]
      def column_strategy?
        Tenant.configuration[:strategy] == :column
      end

      # Check if tenant is required
      # @return [Boolean]
      def require_tenant?
        Tenant.configuration[:require_tenant] == true
      end

      # Check if in unscoped tenant context
      # @return [Boolean]
      def unscoped_tenant_context?
        Thread.current[:unscoped_tenant] == true
      end
    end

    private

    def set_tenant_id
      return unless column_strategy?
      return if send(self.class.tenant_column).present?

      current = self.class.current_tenant
      send("#{self.class.tenant_column}=", current) if current
    end

    def validate_tenant_immutability
      return unless column_strategy?
      return unless strict_mode?
      return unless persisted?

      column = self.class.tenant_column
      changed_method = "#{column}_changed?"
      return unless respond_to?(changed_method) && send(changed_method)

      raise Errors::TenantImmutableError.new(
        tenant_column: column,
        model_class: self.class.name,
        record_id: id
      )
    end

    def column_strategy?
      Tenant.configuration[:strategy] == :column
    end

    def strict_mode?
      Tenant.configuration[:strict_mode] == true
    end
  end
end
