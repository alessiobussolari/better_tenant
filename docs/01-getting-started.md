# Getting Started

Installation and basic setup for BetterTenant.

---

## Requirements

- Ruby >= 3.2.0
- Rails >= 8.1.0
- PostgreSQL (for schema strategy)

## Installation

Add to your Gemfile:

```ruby
gem 'better_tenant'
```

Then run:

```bash
bundle install
```

### Optional Dependencies

For schema-based strategy with PostgreSQL:

```ruby
gem 'pg', '>= 1.0'
```

## CLI Commands

### Installation Commands

```bash
bundle add better_tenant
bundle install
rails generate better_tenant:install
```

### Generator Commands

```bash
# Basic installation (column strategy by default)
rails generate better_tenant:install

# Schema strategy
rails generate better_tenant:install --strategy=schema

# Column strategy with migration
rails generate better_tenant:install --strategy=column --migration --table=articles

# Custom tenant column name
rails generate better_tenant:install --strategy=column --tenant_column=organization_id
```

### Generator Options

| Option | Default | Description |
|--------|---------|-------------|
| `--strategy` | `column` | Tenancy strategy (`schema` or `column`) |
| `--migration` | `false` | Generate migration for tenant column |
| `--table` | `nil` | Table name for migration |
| `--tenant_column` | `tenant_id` | Name of tenant column |

### Rake Tasks

```bash
# List all configured tenants
rake better_tenant:list

# Show current configuration
rake better_tenant:config

# Create a new tenant (schema strategy only)
rake better_tenant:create[tenant_name]

# Drop a tenant (schema strategy only)
rake better_tenant:drop[tenant_name]

# Run migrations for all tenants
rake better_tenant:migrate

# Run a specific rake task for each tenant
rake better_tenant:each[task_name]
```

## Basic Setup

### 1. Generate Initializer

```bash
rails generate better_tenant:install
```

This creates `config/initializers/better_tenant.rb`.

### 2. Configure Strategy

#### Column Strategy (Default)

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names %w[acme globex initech]
end
```

#### Schema Strategy

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names -> { Organization.pluck(:schema_name) }
  config.excluded_models %w[User Organization]
end
```

### 3. Add Migration (Column Strategy)

If using column strategy, add tenant column to your tables:

```ruby
# db/migrate/xxx_add_tenant_id_to_articles.rb
class AddTenantIdToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :tenant_id, :string
    add_index :articles, :tenant_id
  end
end
```

### 4. Include Extension in Models

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end
```

### 5. Add Middleware (Optional)

```ruby
# config/application.rb
class Application < Rails::Application
  config.middleware.use BetterTenant::Middleware, :subdomain
end
```

## Verification

Test your setup in Rails console:

```ruby
# Check configuration
BetterTenant.configuration
# => {:strategy=>:column, :tenant_column=>:tenant_id, ...}

# List tenants
BetterTenant::Tenant.tenant_names
# => ["acme", "globex", "initech"]

# Switch tenant
BetterTenant::Tenant.switch("acme") do
  puts BetterTenant::Tenant.current
  # => "acme"
end
```

## Next Steps

- [Configuration Options](02-configuration.md)
- [Column Strategy Guide](03-column-strategy.md)
- [Schema Strategy Guide](04-schema-strategy.md)
