# frozen_string_literal: true

require "better_tenant/version"

# Load errors first
require "better_tenant/errors/tenant_error"
require "better_tenant/errors/configuration_error"
require "better_tenant/errors/tenant_not_found_error"
require "better_tenant/errors/tenant_context_missing_error"
require "better_tenant/errors/tenant_mismatch_error"
require "better_tenant/errors/tenant_immutable_error"
require "better_tenant/errors/schema_not_found_error"

# Load core components
require "better_tenant/configurator"
require "better_tenant/adapters/abstract_adapter"
require "better_tenant/adapters/postgresql_adapter"
require "better_tenant/adapters/column_adapter"
require "better_tenant/tenant"
require "better_tenant/middleware"
require "better_tenant/active_record_extension"
require "better_tenant/active_job_extension"
require "better_tenant/audit_logger"

# Load Railtie if Rails is available
require "better_tenant/railtie" if defined?(Rails::Railtie)

# Multi-tenancy support for Rails applications.
#
# BetterTenant provides transparent multi-tenancy support for Rails applications.
# It supports both schema-based (PostgreSQL) and column-based strategies,
# inspired by the Apartment gem.
#
# @example Basic usage with column strategy
#   BetterTenant.configure do |config|
#     config.strategy :column
#     config.tenant_column :tenant_id
#     config.tenant_names %w[acme globex initech]
#   end
#
#   # In your application:
#   BetterTenant::Tenant.switch("acme") do
#     Article.all  # Automatically scoped to "acme" tenant
#   end
#
# @example Basic usage with schema strategy
#   BetterTenant.configure do |config|
#     config.strategy :schema
#     config.tenant_names -> { Tenant.pluck(:schema_name) }
#     config.excluded_models %w[User Tenant]
#   end
#
module BetterTenant
  class << self
    # Configure BetterTenant with a block
    # @yield [Configurator] Configuration block
    # @return [void]
    def configure
      configurator = Configurator.new
      yield configurator if block_given?
      Tenant.configure(configurator)
    end

    # Get the current configuration
    # @return [Hash] The configuration hash
    def configuration
      Tenant.configuration
    end

    # Reset the configuration (mainly for testing)
    # @return [void]
    def reset!
      Tenant.reset!
    end
  end
end
