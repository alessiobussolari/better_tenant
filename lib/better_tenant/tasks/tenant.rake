# frozen_string_literal: true

namespace :better_tenant do
  desc "List all configured tenants"
  task list: :environment do
    require_tenant_configuration!

    puts "Configured tenants:"
    BetterTenant::Tenant.tenant_names.each do |tenant|
      status = BetterTenant::Tenant.exists?(tenant) ? "✓" : "✗"
      puts "  #{status} #{tenant}"
    end
  end

  desc "Show current tenant configuration"
  task config: :environment do
    require_tenant_configuration!

    config = BetterTenant::Tenant.configuration
    puts "BetterTenant Configuration:"
    puts "  Strategy: #{config[:strategy]}"
    puts "  Tenant column: #{config[:tenant_column]}" if config[:strategy] == :column
    puts "  Require tenant: #{config[:require_tenant]}"
    puts "  Strict mode: #{config[:strict_mode]}"
    puts "  Excluded models: #{config[:excluded_models].join(', ')}" if config[:excluded_models].any?
    puts "  Persistent schemas: #{config[:persistent_schemas].join(', ')}" if config[:persistent_schemas].any?
    puts "  Schema format: #{config[:schema_format]}" if config[:strategy] == :schema
  end

  desc "Create a new tenant schema (schema strategy only)"
  task :create, [:tenant_name] => :environment do |_t, args|
    require_tenant_configuration!
    require_schema_strategy!

    tenant = args[:tenant_name]
    abort "Usage: rake better_tenant:create[tenant_name]" unless tenant

    puts "Creating tenant: #{tenant}"
    BetterTenant::Tenant.create(tenant)
    puts "Tenant '#{tenant}' created successfully!"
  rescue BetterTenant::Errors::TenantNotFoundError => e
    abort "Error: #{e.message}"
  end

  desc "Drop a tenant schema (schema strategy only)"
  task :drop, [:tenant_name] => :environment do |_t, args|
    require_tenant_configuration!
    require_schema_strategy!

    tenant = args[:tenant_name]
    abort "Usage: rake better_tenant:drop[tenant_name]" unless tenant

    puts "WARNING: This will permanently delete all data in tenant '#{tenant}'!"
    print "Type 'yes' to confirm: "
    confirmation = $stdin.gets.chomp

    if confirmation == "yes"
      BetterTenant::Tenant.drop(tenant)
      puts "Tenant '#{tenant}' dropped successfully!"
    else
      puts "Operation cancelled."
    end
  end

  desc "Run migrations for all tenants (schema strategy only)"
  task migrate: :environment do
    require_tenant_configuration!
    require_schema_strategy!

    puts "Running migrations for all tenants..."
    BetterTenant::Tenant.each do |tenant|
      puts "  Migrating tenant: #{tenant}"
      # Run migrations in tenant context
      Rake::Task["db:migrate"].reenable
      Rake::Task["db:migrate"].invoke
    end
    puts "All tenant migrations completed!"
  end

  desc "Rollback migrations for all tenants (schema strategy only)"
  task rollback: :environment do
    require_tenant_configuration!
    require_schema_strategy!

    puts "Rolling back migrations for all tenants..."
    BetterTenant::Tenant.each do |tenant|
      puts "  Rolling back tenant: #{tenant}"
      Rake::Task["db:rollback"].reenable
      Rake::Task["db:rollback"].invoke
    end
    puts "All tenant rollbacks completed!"
  end

  desc "Seed all tenants"
  task seed: :environment do
    require_tenant_configuration!

    puts "Seeding all tenants..."
    BetterTenant::Tenant.each do |tenant|
      puts "  Seeding tenant: #{tenant}"
      Rake::Task["db:seed"].reenable
      Rake::Task["db:seed"].invoke
    end
    puts "All tenants seeded!"
  end

  desc "Switch to a tenant and open a console"
  task :console, [:tenant_name] => :environment do |_t, args|
    require_tenant_configuration!

    tenant = args[:tenant_name]
    abort "Usage: rake better_tenant:console[tenant_name]" unless tenant

    BetterTenant::Tenant.switch!(tenant)
    puts "Switched to tenant: #{tenant}"
    puts "Starting Rails console..."

    # Start IRB or Rails console
    if defined?(Rails::Console)
      Rails::Console.start(Rails.application)
    else
      require "irb"
      IRB.start
    end
  end

  desc "Execute a task for each tenant"
  task :each, [:task_name] => :environment do |_t, args|
    require_tenant_configuration!

    task_name = args[:task_name]
    abort "Usage: rake better_tenant:each[task_name]" unless task_name

    puts "Running '#{task_name}' for all tenants..."
    BetterTenant::Tenant.each do |tenant|
      puts "  Tenant: #{tenant}"
      Rake::Task[task_name].reenable
      Rake::Task[task_name].invoke
    end
    puts "Task completed for all tenants!"
  end

  private

  def require_tenant_configuration!
    BetterTenant::Tenant.configuration
  rescue BetterTenant::Errors::ConfigurationError
    abort "Error: BetterTenant is not configured. Add configuration in config/initializers/better_tenant.rb"
  end

  def require_schema_strategy!
    strategy = BetterTenant::Tenant.configuration[:strategy]
    return if strategy == :schema

    abort "Error: This task is only available for schema strategy. Current strategy: #{strategy}"
  end
end
