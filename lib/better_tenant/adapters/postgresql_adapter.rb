# frozen_string_literal: true

require_relative "abstract_adapter"

module BetterTenant
  module Adapters
    # PostgreSQL adapter for schema-based multi-tenancy.
    #
    # Uses PostgreSQL's `SET search_path` to isolate tenants at the database level.
    # This provides strong isolation without any application-level query filtering.
    #
    # @example
    #   adapter = PostgresqlAdapter.new(config)
    #   adapter.switch("acme") do
    #     Article.all  # Only sees acme's articles
    #   end
    #
    class PostgresqlAdapter < AbstractAdapter
      # Switch to a tenant permanently
      # @param tenant [String] The tenant name
      # @return [String] The tenant name
      def switch!(tenant)
        validate_tenant!(tenant)

        previous = @current
        run_callback(:before_switch, previous, tenant)

        set_search_path(current_search_path_for(tenant))
        @current = tenant

        run_callback(:after_switch, previous, tenant)
        @current
      end

      # Switch to a tenant for the duration of a block
      # @param tenant [String] The tenant name
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

      # Reset to the default tenant (public schema)
      def reset
        previous = @current
        run_callback(:before_switch, previous, nil)

        set_search_path(default_search_path)
        @current = nil

        run_callback(:after_switch, previous, nil)
      end

      # Create a new tenant schema
      # @param tenant [String] The tenant name
      def create(tenant)
        validate_tenant!(tenant)

        run_callback(:before_create, tenant)

        schema = schema_for(tenant)
        execute_sql("CREATE SCHEMA IF NOT EXISTS #{quote_schema(schema)}")

        # Switch to tenant and run migrations
        switch(tenant) do
          run_callback(:after_create, tenant)
        end
      end

      # Drop a tenant schema
      # @param tenant [String] The tenant name
      def drop(tenant)
        schema = schema_for(tenant)
        execute_sql("DROP SCHEMA IF EXISTS #{quote_schema(schema)} CASCADE")
      end

      # Check if a tenant exists in the tenant_names list
      # @param tenant [String] The tenant name
      # @return [Boolean]
      def exists?(tenant)
        all_tenants.include?(tenant)
      end

      # Check if a schema exists in PostgreSQL
      # @param schema [String] The schema name
      # @return [Boolean]
      def schema_exists?(schema)
        result = execute_sql(
          "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = #{quote_value(schema)})"
        )
        result&.first&.values&.first == true
      rescue StandardError
        false
      end

      # Get the current search path for a tenant
      # @return [String] The search path
      def current_search_path
        current_search_path_for(@current)
      end

      # Get the default search path (public schema)
      # @return [String] The search path
      def default_search_path
        schemas = persistent_schemas + ["public"]
        schemas.join(", ")
      end

      # Iterate over all tenants
      # @yield [tenant] Block to execute for each tenant
      def each_tenant
        all_tenants.each do |tenant|
          switch(tenant) { yield tenant }
        end
      end

      private

      def current_search_path_for(tenant)
        return default_search_path unless tenant

        schema = schema_for(tenant)
        schemas = [schema] + persistent_schemas + ["public"]
        schemas.join(", ")
      end

      def persistent_schemas
        config[:persistent_schemas] || []
      end

      def set_search_path(path)
        execute_sql("SET search_path TO #{path}")
      end

      def execute_sql(sql)
        connection.execute(sql)
      rescue StandardError => e
        Rails.logger.error("[BetterTenant] SQL Error: #{e.message}")
        raise
      end

      def connection
        ActiveRecord::Base.connection
      end

      def quote_schema(schema)
        connection.quote_column_name(schema)
      end

      def quote_value(value)
        connection.quote(value)
      end
    end
  end
end
