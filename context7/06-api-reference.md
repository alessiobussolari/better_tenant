# API Reference

Complete API reference for BetterTenant.

---

## Main Module

### Configure

```ruby
BetterTenant.configure do |config|
  # options
end
```

--------------------------------

### Access Config

```ruby
BetterTenant.configuration
# => Hash
```

--------------------------------

## BetterTenant::Tenant

| Method | Returns | Description |
|--------|---------|-------------|
| `.current` | `String/nil` | Current tenant |
| `.switch!(tenant)` | `String` | Permanent switch |
| `.switch(tenant, &block)` | `Object` | Block switch |
| `.reset` | `void` | Reset to public |
| `.create(tenant)` | `void` | Create schema |
| `.drop(tenant)` | `void` | Drop schema |
| `.exists?(tenant)` | `Boolean` | Check exists |
| `.tenant_names` | `Array` | All tenants |
| `.each(&block)` | `void` | Iterate |

--------------------------------

## ActiveRecordExtension

| Method | Description |
|--------|-------------|
| `.tenantable?` | Is tenantable |
| `.excluded_from_tenancy?` | Is excluded |
| `.tenant_column` | Column name |
| `.current_tenant` | Current tenant |
| `.unscoped_tenant(&block)` | Skip scope |

--------------------------------

## Middleware Elevators

| Elevator | Detection |
|----------|-----------|
| `:subdomain` | `acme.example.com` |
| `:domain` | Full domain |
| `:header` | `X-Tenant` header |
| `:path` | `/acme/...` |
| `Proc` | Custom logic |

--------------------------------

## Errors

| Error | When |
|-------|------|
| `TenantNotFoundError` | Invalid tenant |
| `TenantContextMissingError` | No tenant set |
| `TenantImmutableError` | Changing tenant_id |
| `ConfigurationError` | Invalid config |

--------------------------------

## Configuration Hash

```ruby
{
  strategy: :column,
  tenant_column: :tenant_id,
  tenant_names: [...],
  tenant_model: nil,
  tenant_identifier: :id,
  excluded_models: [],
  persistent_schemas: [],
  schema_format: "%{tenant}",
  elevator: nil,
  excluded_subdomains: [],
  excluded_paths: [],
  require_tenant: true,
  strict_mode: false,
  callbacks: { ... }
}
```

--------------------------------
