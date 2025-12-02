# BetterTenant - Quick Reference

Multi-tenancy for Rails 8.1+ with schema and column strategies.

---

## Documentation

1. [Getting Started](01-getting-started.md)
2. [Configuration](02-configuration.md)
3. [Tenant API](03-tenant-api.md)
4. [Middleware](04-middleware.md)
5. [ActiveJob](05-activejob.md)
6. [API Reference](06-api-reference.md)
7. [Testing](07-testing.md)
8. [Rake Tasks](08-rake-tasks.md)
9. [Generators](09-generators.md)
10. [Troubleshooting](10-troubleshooting.md)
11. [Centralized Login](11-centralized-login.md)

---

## Installation

```bash
bundle add better_tenant
rails generate better_tenant:install
```

---

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

---

## Key Features

- **Column Strategy** - Shared database with tenant_id filtering
- **Schema Strategy** - PostgreSQL schema isolation
- **Middleware** - Auto-detect tenant from requests
- **ActiveJob** - Tenant context in background jobs
- **Callbacks** - Lifecycle hooks

---

## Requirements

- Ruby >= 3.2
- Rails >= 8.1
- PostgreSQL (schema strategy)

---
