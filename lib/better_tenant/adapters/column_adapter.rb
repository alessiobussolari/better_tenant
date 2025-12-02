# frozen_string_literal: true

require_relative "abstract_adapter"

module BetterTenant
  module Adapters
    # Column-based adapter for multi-tenancy using a tenant_id column.
    #
    # This adapter uses a shared database schema with tenant isolation
    # provided by a column (typically `tenant_id`) that is automatically
    # filtered on all queries.
    #
    # @example
    #   adapter = ColumnAdapter.new(config)
    #   adapter.switch("acme") do
    #     Article.all  # WHERE tenant_id = 'acme'
    #   end
    #
    class ColumnAdapter < AbstractAdapter
      # Switch to a tenant permanently
      # @param tenant [String] The tenant name/id
      # @return [String] The tenant name
      def switch!(tenant)
        validate_tenant!(tenant)

        previous = @current
        run_callback(:before_switch, previous, tenant)

        @current = tenant

        run_callback(:after_switch, previous, tenant)
        @current
      end

      # Switch to a tenant for the duration of a block
      # @param tenant [String] The tenant name/id
      # @yield Block to execute in tenant context
      # @return [Object] The block's return value
      def switch(tenant)
        validate_tenant!(tenant)

        previous = @current
        begin
          switch!(tenant)
          yield
        ensure
          if previous
            switch!(previous)
          else
            reset
          end
        end
      end

      # Reset to no tenant (public/shared access)
      def reset
        previous = @current
        run_callback(:before_switch, previous, nil)

        @current = nil

        run_callback(:after_switch, previous, nil)
      end

      # Create a new tenant (no-op for column strategy, just runs callbacks)
      # @param tenant [String] The tenant name/id
      def create(tenant)
        validate_tenant!(tenant)

        run_callback(:before_create, tenant)
        # No schema to create in column strategy
        run_callback(:after_create, tenant)
      end

      # Drop a tenant (no-op for column strategy)
      # In column strategy, dropping a tenant would mean deleting all records
      # with that tenant_id, which is application-specific
      # @param tenant [String] The tenant name/id
      def drop(tenant)
        # No schema to drop in column strategy
        # Application should handle data cleanup if needed
      end

      # Check if a tenant exists in the tenant_names list
      # @param tenant [String] The tenant name/id
      # @return [Boolean]
      def exists?(tenant)
        all_tenants.include?(tenant)
      end

      # Iterate over all tenants
      # @yield [tenant] Block to execute for each tenant
      def each_tenant
        all_tenants.each do |tenant|
          switch(tenant) { yield tenant }
        end
      end

      # Get the tenant column name
      # @return [Symbol] The tenant column
      def tenant_column
        config[:tenant_column]
      end
    end
  end
end
