# BetterTenant

BetterTenant provides transparent multi-tenancy support for Rails 8.1+ applications. It supports both schema-based (PostgreSQL) and column-based strategies, inspired by the Apartment gem.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'better_tenant'
```

Then execute:

```bash
$ bundle install
$ rails generate better_tenant:install
```

## Configuration

Create an initializer `config/initializers/better_tenant.rb`:

```ruby
BetterTenant.configure do |config|
  # Strategy: :schema (PostgreSQL) or :column
  config.strategy :column

  # For column strategy
  config.tenant_column :tenant_id

  # List of tenant names (can be a proc for dynamic loading)
  config.tenant_names %w[acme globex initech]
  # Or: config.tenant_names -> { Tenant.pluck(:subdomain) }

  # Or use tenant_model for automatic configuration (recommended)
  config.tenant_model "Organization"      # Your tenant model class name
  config.tenant_identifier :slug          # Column to identify tenants (default: :id)

  # Require tenant context (default: true)
  config.require_tenant false

  # Models excluded from tenancy
  config.excluded_models %w[User Tenant]
end
```

## Middleware Setup

Add the middleware to your `config/application.rb`:

```ruby
# Header-based tenant detection (X-Tenant header)
config.middleware.use BetterTenant::Middleware, :header

# Or subdomain-based
config.middleware.use BetterTenant::Middleware, :subdomain

# Or path-based (example.com/TENANT/path)
config.middleware.use BetterTenant::Middleware, :path

# Or domain-based
config.middleware.use BetterTenant::Middleware, :domain
```

## Usage

### Switching Tenants

```ruby
# Block-based (recommended)
BetterTenant::Tenant.switch("acme") do
  Article.all  # Automatically scoped to acme tenant
end

# Permanent switch (use with caution)
BetterTenant::Tenant.switch!("acme")
Article.all  # Scoped to acme

# Reset to default
BetterTenant::Tenant.reset
```

### In Models (Column Strategy)

```ruby
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end
```

### In Background Jobs

```ruby
class MyJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(article_id)
    # Tenant context is automatically restored
    Article.find(article_id)
  end
end
```

## Strategies

### Column Strategy

Uses a `tenant_id` column to scope data. All tenants share the same database tables.

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
end
```

### Schema Strategy (PostgreSQL)

Creates separate PostgreSQL schemas for each tenant. Provides stronger data isolation.

```ruby
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names -> { Tenant.pluck(:schema_name) }
  config.excluded_models %w[Tenant User]
end
```

## Tenant Model Configuration

Instead of manually configuring `tenant_names` and `excluded_models`, you can use `tenant_model` for automatic configuration:

```ruby
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_model "Organization"    # Your tenant model class
  config.tenant_identifier :slug        # Column used as tenant identifier (default: :id)
  config.persistent_schemas %w[shared]
  config.schema_format "tenant_%{tenant}"
end
```

This automatically:
- Creates a dynamic `tenant_names` Proc that queries `Organization.pluck(:slug)`
- Adds `"Organization"` to `excluded_models` (tenant table stays in public schema)

### Examples

```ruby
# Using ID as identifier (default)
config.tenant_model "Tenant"
# tenant_names will call: Tenant.pluck(:id).map(&:to_s)

# Using slug
config.tenant_model "Organization"
config.tenant_identifier :slug
# tenant_names will call: Organization.pluck(:slug).map(&:to_s)

# Using subdomain
config.tenant_model "Account"
config.tenant_identifier :subdomain
# tenant_names will call: Account.pluck(:subdomain).map(&:to_s)

# Using custom column
config.tenant_model "BusinessUnit"
config.tenant_identifier :database_name
# tenant_names will call: BusinessUnit.pluck(:database_name).map(&:to_s)
```

**Note:** If you explicitly set `tenant_names`, it takes precedence over the auto-generated Proc from `tenant_model`.

## Rake Tasks

```bash
# List all tenants
rake better_tenant:list

# Show configuration
rake better_tenant:config

# Create a new tenant (schema strategy)
rake better_tenant:create[tenant_name]

# Drop a tenant (schema strategy)
rake better_tenant:drop[tenant_name]

# Run migrations for all tenants
rake better_tenant:migrate

# Run a task for each tenant
rake better_tenant:each[task_name]
```

## License

MIT License. See [MIT-LICENSE](MIT-LICENSE) for details.
