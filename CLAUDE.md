# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BetterTenant is a **multi-tenancy gem for Rails 8.1+** that provides transparent tenant isolation. It supports two strategies:

- **Column Strategy**: Shared database with `tenant_id` column filtering
- **Schema Strategy**: PostgreSQL schema-based isolation (`SET search_path`)

Inspired by the Apartment gem, modernized for Rails 8.1+ with Ruby 3.2+ features.

## Key Files

| File/Directory | Purpose |
|----------------|---------|
| `lib/better_tenant.rb` | Main entry point, loads all components |
| `lib/better_tenant/tenant.rb` | Core tenant API (switch, create, drop, etc.) |
| `lib/better_tenant/configurator.rb` | Configuration DSL |
| `lib/better_tenant/middleware.rb` | Rack middleware for auto tenant detection |
| `lib/better_tenant/active_record_extension.rb` | Model mixin for tenant scoping |
| `lib/better_tenant/active_job_extension.rb` | Job mixin for tenant serialization |
| `lib/better_tenant/adapters/` | Strategy implementations |

## Architecture

```
BetterTenant
├── Tenant (facade API)
│   ├── ColumnAdapter (tenant_id filtering)
│   └── PostgresqlAdapter (schema isolation)
├── Configurator (DSL)
├── Middleware (request tenant detection)
├── ActiveRecordExtension (model scoping)
└── ActiveJobExtension (job serialization)
```

## Common Commands

```bash
bundle exec rspec              # Run tests
bundle exec rspec spec/better_tenant/  # Run unit tests
bundle exec rubocop            # Run linter
bundle exec rubocop -a         # Auto-fix linting issues
bundle exec rake build         # Build the gem
bundle exec rake install       # Install locally
```

## Testing

The test suite uses both SQLite (column strategy) and PostgreSQL (schema strategy):

```bash
# Start PostgreSQL container (for schema strategy tests)
docker-compose up -d

# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/better_tenant/tenant_spec.rb

# Run PostgreSQL integration tests
bundle exec rspec spec/better_tenant/integration/postgresql_schema_spec.rb
```

## Code Patterns

### Configuration Pattern

```ruby
BetterTenant.configure do |config|
  config.strategy :column           # or :schema
  config.tenant_column :tenant_id
  config.tenant_names %w[acme globex]
end
```

### Tenant Switching Pattern

```ruby
# Block-based (recommended)
BetterTenant::Tenant.switch("acme") do
  Article.all  # Scoped to acme
end

# Permanent switch
BetterTenant::Tenant.switch!("acme")
BetterTenant::Tenant.reset
```

### Model Extension Pattern (Column Strategy)

```ruby
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end
```

### Job Extension Pattern

```ruby
class MyJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(id)
    Model.find(id)  # Tenant auto-restored
  end
end
```

### Middleware Pattern

```ruby
# config/application.rb
config.middleware.use BetterTenant::Middleware, :subdomain
```

## Important Implementation Details

1. **Thread Safety**: Tenant context stored in adapter instance, not Thread.current
2. **Callbacks**: Run via `run_callback(name, *args)` in adapters
3. **Schema Format**: Uses `%{tenant}` placeholder (e.g., `"tenant_%{tenant}"`)
4. **Validation**: `validate_tenant!` checks against `all_tenants` list
5. **PostgreSQL**: Uses `SET search_path TO schema, public` for isolation

## Error Classes

| Error | When Raised |
|-------|-------------|
| `TenantNotFoundError` | Tenant not in tenant_names list |
| `TenantContextMissingError` | Operation without tenant when required |
| `TenantImmutableError` | Changing tenant_id in strict mode |
| `ConfigurationError` | Invalid configuration values |

## Adding New Features

1. Add configuration option to `Configurator`
2. Update `to_h` to include new option
3. Implement in appropriate adapter
4. Add tests for both strategies
5. Update documentation in `docs/` and `context7/`

## Response Format Convention

This gem does not enforce response formats. It focuses on tenant isolation at the data layer.
