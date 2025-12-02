# BetterTenant Documentation

Complete documentation for BetterTenant multi-tenancy gem.

## Table of Contents

1. [Getting Started](01-getting-started.md)
2. [Configuration](02-configuration.md)
3. [Column Strategy](03-column-strategy.md)
4. [Schema Strategy](04-schema-strategy.md)
5. [Middleware & Elevators](05-middleware.md)
6. [ActiveJob Integration](06-activejob.md)
7. [Callbacks](07-callbacks.md)
8. [API Reference](08-api-reference.md)

## Quick Links

- [Installation](01-getting-started.md#installation)
- [CLI Commands](01-getting-started.md#cli-commands)
- [Configuration Options](02-configuration.md#options-reference)
- [Column Strategy Setup](03-column-strategy.md#basic-setup)
- [Schema Strategy Setup](04-schema-strategy.md#basic-setup)
- [Middleware Configuration](05-middleware.md#setup)
- [Background Jobs](06-activejob.md#usage)

## Overview

BetterTenant provides transparent multi-tenancy support for Rails 8.1+ applications. It offers two isolation strategies:

### Column Strategy

Uses a shared database with tenant isolation via a `tenant_id` column. All tenants share the same tables, with automatic filtering applied to queries.

**Pros:**
- Simple setup
- Works with any database
- Easy migrations
- Lower overhead

**Cons:**
- Requires column on every tenant table
- Data isolation at application level

### Schema Strategy

Uses PostgreSQL schemas to provide database-level isolation. Each tenant has its own schema with separate tables.

**Pros:**
- Strong database-level isolation
- No column required on tables
- Better for large datasets per tenant
- Easier per-tenant backups

**Cons:**
- PostgreSQL only
- More complex migrations
- Schema management overhead

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Application                          │
├─────────────────────────────────────────────────────────────┤
│                    BetterTenant::Middleware                 │
│                    (Tenant Detection)                       │
├─────────────────────────────────────────────────────────────┤
│                    BetterTenant::Tenant                     │
│                    (Tenant Management)                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │   ColumnAdapter     │    │  PostgresqlAdapter  │        │
│  │  (tenant_id col)    │    │  (schema isolation) │        │
│  └─────────────────────┘    └─────────────────────┘        │
├─────────────────────────────────────────────────────────────┤
│                       ActiveRecord                          │
├─────────────────────────────────────────────────────────────┤
│                        Database                             │
└─────────────────────────────────────────────────────────────┘
```

## Support

- [GitHub Issues](https://github.com/alessiobussolari/better_tenant/issues)
- [Documentation](https://rubydoc.info/gems/better_tenant)
