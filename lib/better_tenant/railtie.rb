# frozen_string_literal: true

module BetterTenant
  # Rails integration for BetterTenant.
  #
  # This Railtie provides:
  # - Automatic loading of configuration
  # - Rake tasks for tenant management
  # - Generator hooks
  #
  class Railtie < ::Rails::Railtie
    # Load configuration
    config.better_tenant = ActiveSupport::OrderedOptions.new

    # Load rake tasks
    rake_tasks do
      load File.expand_path("tasks/tenant.rake", __dir__)
    end

    # Provide generators
    generators do
      require_relative "../generators/better_tenant/install_generator" if defined?(Rails::Generators)
    end
  end
end
