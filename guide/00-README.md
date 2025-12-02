# BetterTenant Guides

Step-by-step tutorials for BetterTenant.

## Available Guides

| Guide | Description | Time |
|-------|-------------|------|
| [Quick Start](01-quick-start.md) | Get running in 5 minutes | 5 min |
| [Building a SaaS App](02-building-saas-app.md) | Complete SaaS tutorial with column strategy | 20 min |
| [Building Multi-Tenant API](03-building-multi-tenant-api.md) | API with schema strategy | 25 min |
| [Real World Example](04-real-world-example.md) | Full multi-tenant CRM | 30 min |

## Prerequisites

- Ruby >= 3.2
- Rails >= 8.1
- PostgreSQL (for schema strategy guides)
- Basic knowledge of Rails and ActiveRecord

## Guide Structure

Each guide follows a consistent structure:

1. **What You'll Build** - Overview of the end result
2. **Prerequisites** - Required setup and knowledge
3. **Step-by-Step Instructions** - Detailed implementation
4. **Testing** - How to verify your implementation
5. **Summary** - What you learned
6. **Next Steps** - Where to go from here

## Choosing the Right Strategy

### Column Strategy
Best for:
- Quick setup
- Any database
- Smaller tenants
- Shared schema/migrations

Start with: [Building a SaaS App](02-building-saas-app.md)

### Schema Strategy
Best for:
- Strong isolation
- PostgreSQL databases
- Large tenants
- Per-tenant backups

Start with: [Building Multi-Tenant API](03-building-multi-tenant-api.md)

## Common Patterns

These guides cover common multi-tenancy patterns:

- **Subdomain-based tenancy** - acme.example.com
- **Header-based tenancy** - API with X-Tenant header
- **Path-based tenancy** - example.com/acme/dashboard
- **Custom tenant resolution** - JWT tokens, session, etc.
