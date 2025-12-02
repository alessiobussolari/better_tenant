# Quick Start Guide

Get up and running with BetterTenant in 5 minutes.

---

## Step 1: Install the Gem

```bash
bundle add better_tenant
bundle install
```

## Step 2: Generate Configuration

```bash
rails generate better_tenant:install
```

This creates `config/initializers/better_tenant.rb`.

## Step 3: Configure Your Strategy

### Option A: Column Strategy (Recommended for beginners)

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names %w[acme globex initech]
end
```

Add tenant column to your tables:

```bash
rails generate migration AddTenantIdToArticles tenant_id:string:index
rails db:migrate
```

### Option B: Schema Strategy (PostgreSQL)

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names %w[acme globex initech]
  config.excluded_models %w[User]
end
```

## Step 4: Setup Models

Include the extension in tenanted models (column strategy only):

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end
```

## Step 5: Add Middleware (Optional)

```ruby
# config/application.rb
class Application < Rails::Application
  # Subdomain: acme.example.com -> "acme"
  config.middleware.use BetterTenant::Middleware, :subdomain
end
```

## Step 6: Test It

```ruby
# Rails console
rails console

# Check configuration
BetterTenant.configuration
# => {:strategy=>:column, ...}

# Switch tenant
BetterTenant::Tenant.switch("acme") do
  puts BetterTenant::Tenant.current
  # => "acme"

  # Create scoped data
  Article.create!(title: "Hello from Acme")
end

# Different tenant
BetterTenant::Tenant.switch("globex") do
  Article.count
  # => 0 (no Globex articles)
end
```

## What You Get

By including BetterTenant, you have access to:

- **Automatic Query Scoping** - All queries filtered by tenant
- **Automatic tenant_id Assignment** - New records get tenant set
- **Thread-Safe Context** - Safe for concurrent requests
- **Middleware Support** - Auto-detect tenant from requests
- **Background Job Support** - Tenant context in ActiveJob

## Quick Reference

```ruby
# Switch tenant (block)
BetterTenant::Tenant.switch("acme") { Article.all }

# Switch tenant (permanent)
BetterTenant::Tenant.switch!("acme")

# Reset to public
BetterTenant::Tenant.reset

# Get current tenant
BetterTenant::Tenant.current

# Check if tenant exists
BetterTenant::Tenant.exists?("acme")

# List all tenants
BetterTenant::Tenant.tenant_names

# Cross-tenant operation
Article.unscoped_tenant { Article.count }
```

## Next Steps

- Read the [Configuration Guide](../docs/02-configuration.md)
- Follow [Building a SaaS App](02-building-saas-app.md) for a complete tutorial
- Check [Schema Strategy Guide](../docs/04-schema-strategy.md) for PostgreSQL
