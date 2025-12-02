# BetterTenant

### Multi-tenancy for Rails 8.1+ applications

<div align="center">

[![Gem Version](https://badge.fury.io/rb/better_tenant.svg)](https://badge.fury.io/rb/better_tenant)
[![CI](https://github.com/alessiobussolari/better_tenant/actions/workflows/ci.yml/badge.svg)](https://github.com/alessiobussolari/better_tenant/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/alessiobussolari/better_tenant/branch/main/graph/badge.svg)](https://codecov.io/gh/alessiobussolari/better_tenant)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-ruby.svg)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%208.1-CC0000.svg)](https://rubyonrails.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[![Downloads](https://img.shields.io/gem/dt/better_tenant.svg)](https://rubygems.org/gems/better_tenant)
[![Documentation](https://img.shields.io/badge/docs-rubydoc.info-blue.svg)](https://rubydoc.info/gems/better_tenant)
[![GitHub issues](https://img.shields.io/github/issues/alessiobussolari/better_tenant.svg)](https://github.com/alessiobussolari/better_tenant/issues)
[![GitHub stars](https://img.shields.io/github/stars/alessiobussolari/better_tenant.svg)](https://github.com/alessiobussolari/better_tenant/stargazers)
[![Contributors](https://img.shields.io/github/contributors/alessiobussolari/better_tenant.svg)](https://github.com/alessiobussolari/better_tenant/graphs/contributors)

[Features](#-features) • [Installation](#-installation) • [Quick Start](#-quick-start) • [Usage](#-usage) • [Configuration](#%EF%B8%8F-configuration) • [API Reference](#-api-reference)

</div>

---

Transparent multi-tenancy support for Rails applications with schema-based (PostgreSQL) and column-based isolation strategies. Inspired by the Apartment gem, modernized for Rails 8.1+.

## ✨ Features

- **Dual Strategy Support** - Choose between schema-based (PostgreSQL) or column-based isolation
- **Automatic Tenant Scoping** - Queries are automatically filtered by tenant context
- **Flexible Tenant Detection** - Multiple elevators: subdomain, domain, header, path, or custom Proc
- **Thread-Safe** - Safe for multi-threaded environments with proper context isolation
- **ActiveJob Integration** - Automatic tenant serialization in background jobs
- **Rack Middleware** - Automatic tenant switching based on request
- **Rails 8.1+ Native** - Built specifically for modern Rails applications
- **Comprehensive Callbacks** - Hooks for tenant creation, switching, and lifecycle events

## 💡 Philosophy

BetterTenant was created to provide a modern, Rails 8.1+ compatible multi-tenancy solution. Traditional gems like Apartment have served the community well, but BetterTenant takes a fresh approach:

- **Zero Legacy** - No backward compatibility concerns, clean API design
- **Strategy Flexibility** - First-class support for both schema and column strategies
- **Modern Ruby** - Leverages Ruby 3.2+ features and patterns
- **Minimal Configuration** - Sensible defaults with powerful customization options

## 📦 Installation

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

## 🚀 Quick Start

### Column Strategy (Shared Database)

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names %w[acme globex initech]
end

# app/models/article.rb
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end

# Usage
BetterTenant::Tenant.switch("acme") do
  Article.all  # Automatically WHERE tenant_id = 'acme'
end
```

### Schema Strategy (PostgreSQL)

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names -> { Organization.pluck(:schema_name) }
  config.excluded_models %w[User Organization]
end

# Usage
BetterTenant::Tenant.switch("acme") do
  Article.all  # Queries the "acme" schema
end
```

## 💻 CLI Commands

### Installation

```bash
bundle add better_tenant
bundle install
rails generate better_tenant:install
```

### Generators

| Command | Description |
|---------|-------------|
| `rails g better_tenant:install` | Create initializer with default configuration |
| `rails g better_tenant:install --strategy=schema` | Create initializer for schema strategy |
| `rails g better_tenant:install --strategy=column --migration --table=articles` | Create initializer and migration |

### Rake Tasks

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

# Rollback migrations for all tenants
rake better_tenant:rollback

# Seed all tenants
rake better_tenant:seed

# Open console in tenant context
rake better_tenant:console[tenant_name]

# Run a task for each tenant
rake better_tenant:each[task_name]
```

See [Rake Tasks Documentation](docs/10-rake-tasks.md) for complete details.

## 📖 Usage

### Basic Usage

```ruby
# Switch tenant for a block
BetterTenant::Tenant.switch("acme") do
  Article.all  # Scoped to acme
  Article.create!(title: "Hello")  # tenant_id automatically set
end

# Permanent switch
BetterTenant::Tenant.switch!("acme")
Article.all  # Scoped to acme until reset

# Reset to public/default
BetterTenant::Tenant.reset

# Check current tenant
BetterTenant::Tenant.current  # => "acme" or nil
```

### Using Middleware

```ruby
# config/application.rb
class Application < Rails::Application
  # Subdomain elevator: acme.example.com -> "acme"
  config.middleware.use BetterTenant::Middleware, :subdomain

  # Or header elevator: X-Tenant header
  config.middleware.use BetterTenant::Middleware, :header

  # Or path elevator: example.com/acme/articles -> "acme"
  config.middleware.use BetterTenant::Middleware, :path

  # Or custom Proc
  config.middleware.use BetterTenant::Middleware, ->(request) {
    request.params["tenant"]
  }
end
```

### ActiveJob Integration

```ruby
class ProcessOrderJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(order_id)
    # Tenant context is automatically restored
    order = Order.find(order_id)
    order.process!
  end
end

# Enqueueing preserves tenant
BetterTenant::Tenant.switch("acme") do
  ProcessOrderJob.perform_later(order.id)
  # Job will execute in "acme" context
end
```

### Cross-Tenant Operations

```ruby
# Iterate over all tenants
BetterTenant::Tenant.each do |tenant|
  puts "Processing #{tenant}..."
  Article.count
end

# Unscoped access (column strategy)
Article.unscoped_tenant do
  Article.all  # Returns all articles across tenants
end
```

### Tenant Management

```ruby
# Create a tenant (schema strategy creates the schema)
BetterTenant::Tenant.create("new_tenant")

# Drop a tenant (schema strategy drops the schema)
BetterTenant::Tenant.drop("old_tenant")

# Check if tenant exists
BetterTenant::Tenant.exists?("acme")  # => true

# List all tenants
BetterTenant::Tenant.tenant_names  # => ["acme", "globex", "initech"]
```

### Tenant Model Configuration

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

## ⚙️ Configuration

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  # Strategy: :column or :schema
  config.strategy :column

  # Column name (column strategy)
  config.tenant_column :tenant_id

  # Tenant names - Array or Proc
  config.tenant_names %w[acme globex initech]
  # Or dynamic:
  config.tenant_names -> { Organization.pluck(:slug) }

  # Or use tenant_model for automatic setup
  config.tenant_model "Organization"
  config.tenant_identifier :slug  # defaults to :id

  # Models excluded from tenancy (remain in public schema)
  config.excluded_models %w[User Organization]

  # Persistent schemas (always in search_path for schema strategy)
  config.persistent_schemas %w[shared extensions]

  # Schema naming format (schema strategy)
  config.schema_format "tenant_%{tenant}"

  # Elevator configuration
  config.elevator :subdomain
  config.excluded_subdomains %w[www admin api]
  config.excluded_paths %w[api admin assets]

  # Behavior options
  config.require_tenant true    # Raise error if no tenant context
  config.strict_mode false      # Prevent changing tenant_id on records

  # Audit logging
  config.audit_violations true  # Log tenant violation attempts
  config.audit_access false     # Log all tenant access

  # Callbacks
  config.before_create { |tenant| puts "Creating #{tenant}" }
  config.after_create { |tenant| puts "Created #{tenant}" }
  config.before_switch { |from, to| puts "Switching #{from} -> #{to}" }
  config.after_switch { |from, to| puts "Switched to #{to}" }
end
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `strategy` | `Symbol` | `:column` | Isolation strategy (`:column` or `:schema`) |
| `tenant_column` | `Symbol` | `:tenant_id` | Column name for tenant filtering |
| `tenant_names` | `Array/Proc` | `[]` | List of valid tenant names |
| `tenant_model` | `String` | `nil` | Model class to query for tenants |
| `tenant_identifier` | `Symbol` | `:id` | Column to use as tenant identifier |
| `excluded_models` | `Array` | `[]` | Models that bypass tenant filtering |
| `persistent_schemas` | `Array` | `[]` | Schemas always in search_path |
| `schema_format` | `String` | `"%{tenant}"` | Schema naming template |
| `elevator` | `Symbol/Proc` | `nil` | Tenant detection method |
| `excluded_subdomains` | `Array` | `[]` | Subdomains to ignore |
| `excluded_paths` | `Array` | `[]` | Path segments to ignore |
| `require_tenant` | `Boolean` | `true` | Require tenant context |
| `strict_mode` | `Boolean` | `false` | Prevent tenant_id changes |
| `audit_violations` | `Boolean` | `false` | Log violation attempts |
| `audit_access` | `Boolean` | `false` | Log all tenant access |

## 📚 API Reference

### BetterTenant Module

| Method | Description |
|--------|-------------|
| `.configure { \|config\| }` | Configure BetterTenant |
| `.configuration` | Get current configuration hash |
| `.reset!` | Reset configuration (for testing) |

### BetterTenant::Tenant

| Method | Description |
|--------|-------------|
| `.current` | Get current tenant name |
| `.switch!(tenant)` | Switch tenant permanently |
| `.switch(tenant) { }` | Switch tenant for block |
| `.reset` | Reset to default/public |
| `.create(tenant)` | Create a tenant |
| `.drop(tenant)` | Drop a tenant |
| `.exists?(tenant)` | Check if tenant exists |
| `.tenant_names` | Get all tenant names |
| `.each { \|tenant\| }` | Iterate over tenants |
| `.excluded_model?(name)` | Check if model is excluded |

### BetterTenant::ActiveRecordExtension

| Method | Description |
|--------|-------------|
| `.tenantable?` | Check if model is tenantable |
| `.excluded_from_tenancy?` | Check if model is excluded |
| `.tenant_column` | Get tenant column name |
| `.current_tenant` | Get current tenant |
| `.unscoped_tenant { }` | Execute without tenant scope |

### BetterTenant::Middleware

| Elevator | Detection Method |
|----------|-----------------|
| `:subdomain` | `acme.example.com` -> `"acme"` |
| `:domain` | Full domain as tenant |
| `:header` | `X-Tenant` header value |
| `:path` | `/acme/articles` -> `"acme"` |
| `Proc` | Custom extraction logic |

## 📖 Documentation

Complete documentation is available in the [docs](docs/) folder:

- [Getting Started](docs/01-getting-started.md)
- [Configuration](docs/02-configuration.md)
- [Column Strategy](docs/03-column-strategy.md)
- [Schema Strategy](docs/04-schema-strategy.md)
- [Middleware & Elevators](docs/05-middleware.md)
- [ActiveJob Integration](docs/06-activejob.md)
- [Callbacks](docs/07-callbacks.md)
- [API Reference](docs/08-api-reference.md)
- [Testing Guide](docs/09-testing.md)
- [Rake Tasks](docs/10-rake-tasks.md)
- [Generators](docs/11-generators.md)
- [Troubleshooting & FAQ](docs/12-troubleshooting.md)
- [Audit Logging](docs/13-audit-logging.md)
- [Centralized Login](docs/14-centralized-login.md)

## 🧪 Testing

```bash
bundle exec rspec
bundle exec rubocop
```

### Test Setup

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    BetterTenant.reset!
  end

  config.around(:each, :tenant) do |example|
    BetterTenant.configure do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[test_tenant]
    end

    BetterTenant::Tenant.switch("test_tenant") do
      example.run
    end
  end
end

# Usage in specs
describe Article, :tenant do
  it "creates article in tenant context" do
    article = Article.create!(title: "Test")
    expect(article.tenant_id).to eq("test_tenant")
  end
end
```

## 📋 Requirements

- Ruby >= 3.2.0
- Rails >= 8.1.0
- PostgreSQL (for schema strategy)

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Ensure code style compliance (`bundle exec rubocop`)
6. Commit your changes (`git commit -am 'Add new feature'`)
7. Push to the branch (`git push origin feature/my-feature`)
8. Create a Pull Request

## 📄 License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 👤 Author

Alessio Bussolari - [alessio.bussolari@pandev.it](mailto:alessio.bussolari@pandev.it)

- GitHub: [@alessiobussolari](https://github.com/alessiobussolari)
- Repository: [https://github.com/alessiobussolari/better_tenant](https://github.com/alessiobussolari/better_tenant)
