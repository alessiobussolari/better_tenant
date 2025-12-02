# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module BetterTenant
  module Generators
    # Generator for setting up BetterTenant in a Rails application.
    #
    # @example Generate initializer only
    #   rails generate better_tenant:install
    #
    # @example Generate initializer with schema strategy
    #   rails generate better_tenant:install --strategy=schema
    #
    # @example Generate initializer with column strategy and migration
    #   rails generate better_tenant:install --strategy=column --migration --table=articles
    #
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :strategy, type: :string, default: "column",
        desc: "Tenancy strategy (schema or column)"
      class_option :migration, type: :boolean, default: false,
        desc: "Generate migration to add tenant_id column (column strategy only)"
      class_option :table, type: :string, default: nil,
        desc: "Table name for tenant_id migration"
      class_option :tenant_column, type: :string, default: "tenant_id",
        desc: "Name of the tenant column"

      def self.next_migration_number(dirname)
        if ActiveRecord::Base.timestamped_migrations
          Time.now.utc.strftime("%Y%m%d%H%M%S")
        else
          "%.3d" % (current_migration_number(dirname) + 1)
        end
      end

      def create_initializer
        template "initializer.rb.tt", "config/initializers/better_tenant.rb"
      end

      def create_migration
        return unless options[:migration] && options[:strategy] == "column"
        return unless options[:table]

        migration_template(
          "add_tenant_id_migration.rb.tt",
          "db/migrate/add_#{options[:tenant_column]}_to_#{options[:table]}.rb"
        )
      end

      def create_middleware_config
        inject_into_file "config/application.rb",
          after: "class Application < Rails::Application\n" do
          <<~RUBY.indent(4)
            # BetterTenant middleware for automatic tenant switching
            # Uncomment and configure the elevator type as needed:
            # config.middleware.use BetterTenant::Middleware, :subdomain
            # config.middleware.use BetterTenant::Middleware, :header
            # config.middleware.use BetterTenant::Middleware, :path
            # config.middleware.use BetterTenant::Middleware, ->(request) { request.host.split('.').first }

          RUBY
        end
      end

      def show_post_install_message
        say ""
        say "BetterTenant has been installed!", :green
        say ""
        say "Next steps:", :yellow
        say "  1. Edit config/initializers/better_tenant.rb to configure your tenants"
        say "  2. Uncomment the middleware line in config/application.rb"
        say "  3. Include BetterTenant::ActiveRecordExtension in your models"
        say ""
        say "Example model setup:"
        say "  class Article < ApplicationRecord"
        say "    include BetterTenant::ActiveRecordExtension"
        say "  end"
        say ""
      end

      private

      def strategy
        options[:strategy]
      end

      def tenant_column
        options[:tenant_column]
      end

      def table_name
        options[:table]
      end
    end
  end
end
