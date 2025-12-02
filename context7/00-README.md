# BetterTenant - Quick Reference

Multi-tenancy for Rails 8.1+ with schema and column strategies.

---

## Installation

```bash
bundle add better_tenant
rails generate better_tenant:install
```

--------------------------------

## Basic Usage

```ruby
# Switch tenant (block)
BetterTenant::Tenant.switch("acme") do
  Article.all  # Scoped to acme
end

# Permanent switch
BetterTenant::Tenant.switch!("acme")

# Reset
BetterTenant::Tenant.reset

# Current tenant
BetterTenant::Tenant.current
```

--------------------------------

## Key Features

- **Column Strategy** - Shared database with tenant_id filtering
- **Schema Strategy** - PostgreSQL schema isolation
- **Middleware** - Auto-detect tenant from requests
- **ActiveJob** - Tenant context in background jobs
- **Callbacks** - Lifecycle hooks

--------------------------------

## Requirements

- Ruby >= 3.2
- Rails >= 8.1
- PostgreSQL (schema strategy)

--------------------------------
