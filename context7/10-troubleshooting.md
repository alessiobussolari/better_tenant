# Troubleshooting - Quick Reference

Common issues and solutions for BetterTenant.

---

## Error Reference

| Error | Cause | Solution |
|-------|-------|----------|
| `TenantNotFoundError` | Tenant not in list | Add to `tenant_names` |
| `TenantContextMissingError` | No tenant set | Set tenant before operation |
| `TenantImmutableError` | Changing tenant_id | Disable `strict_mode` |
| `SchemaNotFoundError` | Schema missing | Run `Tenant.create(name)` |
| `ConfigurationError` | Invalid config | Check strategy/elevator |

---

## Common Issues

### Records not filtered

```ruby
# 1. Add extension to model
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end

# 2. Set tenant context
BetterTenant::Tenant.switch!("acme")

# 3. Enable require_tenant
config.require_tenant true
```

### tenant_id not set

```ruby
# Ensure tenant context when creating
BetterTenant::Tenant.switch("acme") do
  Article.create!(title: "Test")  # tenant_id = "acme"
end
```

### Schema not found

```bash
# Create schema first
rake better_tenant:create[acme]
```

### Middleware not detecting tenant

```ruby
# Check elevator config
config.elevator :subdomain
config.excluded_subdomains %w[www admin]

# Debug with custom Proc
config.middleware.use BetterTenant::Middleware, ->(req) {
  Rails.logger.debug "Host: #{req.host}"
  req.subdomain
}
```

---

## Debug Commands

```ruby
# Check configuration
BetterTenant::Tenant.configuration

# Check current tenant
BetterTenant::Tenant.current

# Check search_path (schema strategy)
ActiveRecord::Base.connection.execute("SHOW search_path")

# Test tenant exists
BetterTenant::Tenant.exists?("acme")
```

---

## FAQ

**Q: Works with MySQL?**
A: Column strategy yes, schema strategy PostgreSQL only.

**Q: Can I use integer tenant_id?**
A: Yes, just match `tenant_names` type.

**Q: How to query across tenants?**
A: `Article.unscoped_tenant { Article.all }`

**Q: Job runs in wrong tenant?**
A: Add `include BetterTenant::ActiveJobExtension` to job class.

**Q: How to handle invalid tenant in request?**
A: Rescue `TenantNotFoundError` in controller.
