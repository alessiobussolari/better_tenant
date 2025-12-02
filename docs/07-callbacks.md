# Callbacks

Lifecycle hooks for tenant operations.

---

## Overview

BetterTenant provides callbacks for key tenant lifecycle events:

- **before_create** / **after_create** - Tenant creation (schema strategy)
- **before_switch** / **after_switch** - Tenant context switching

## Available Callbacks

### before_create

Called before a tenant is created (schema strategy):

```ruby
BetterTenant.configure do |config|
  config.before_create do |tenant|
    Rails.logger.info "Creating tenant: #{tenant}"
    # Validation, pre-setup logic
  end
end
```

### after_create

Called after a tenant is created, within the tenant context:

```ruby
BetterTenant.configure do |config|
  config.after_create do |tenant|
    Rails.logger.info "Created tenant: #{tenant}"

    # Seed initial data (runs in tenant context)
    Category.create!(name: "General")
    Setting.create!(key: "theme", value: "default")
    Role.create!(name: "Admin", permissions: [:all])
  end
end
```

### before_switch

Called before switching tenant context:

```ruby
BetterTenant.configure do |config|
  config.before_switch do |from_tenant, to_tenant|
    Rails.logger.info "Switching: #{from_tenant || 'none'} -> #{to_tenant || 'none'}"
  end
end
```

### after_switch

Called after tenant context has been switched:

```ruby
BetterTenant.configure do |config|
  config.after_switch do |from_tenant, to_tenant|
    Rails.logger.info "Switched to: #{to_tenant || 'public'}"

    # Post-switch logic
    Thread.current[:tenant_switched_at] = Time.current
  end
end
```

## Callback Arguments

### Create Callbacks

| Callback | Arguments | Context |
|----------|-----------|---------|
| `before_create` | `tenant` | Before schema creation |
| `after_create` | `tenant` | Within new tenant context |

### Switch Callbacks

| Callback | Arguments | Context |
|----------|-----------|---------|
| `before_switch` | `from_tenant, to_tenant` | Before search_path change |
| `after_switch` | `from_tenant, to_tenant` | After search_path change |

**Note:** `from_tenant` or `to_tenant` may be `nil` when switching to/from public.

## Common Use Cases

### Seeding Data on Create

```ruby
BetterTenant.configure do |config|
  config.after_create do |tenant|
    # Create default categories
    Category.create!([
      { name: "General", position: 1 },
      { name: "News", position: 2 },
      { name: "Updates", position: 3 }
    ])

    # Create default settings
    Setting.create!(key: "site_name", value: tenant.titleize)
    Setting.create!(key: "theme", value: "default")

    # Create admin role
    Role.create!(name: "Administrator", permissions: %w[manage_all])
  end
end
```

### Audit Logging

```ruby
BetterTenant.configure do |config|
  config.after_switch do |from, to|
    AuditLog.create!(
      event: "tenant_switch",
      from_tenant: from,
      to_tenant: to,
      timestamp: Time.current,
      request_id: Current.request_id
    )
  end
end
```

### Cache Warming

```ruby
BetterTenant.configure do |config|
  config.after_switch do |from, to|
    next unless to  # Skip if switching to public

    # Warm tenant-specific cache
    Rails.cache.fetch("tenant_#{to}_settings", expires_in: 1.hour) do
      Setting.all.index_by(&:key)
    end
  end
end
```

### Notification on Create

```ruby
BetterTenant.configure do |config|
  config.before_create do |tenant|
    Rails.logger.info "[TENANT] Starting creation: #{tenant}"
  end

  config.after_create do |tenant|
    Rails.logger.info "[TENANT] Completed creation: #{tenant}"

    # Notify admin
    AdminMailer.tenant_created(tenant).deliver_later

    # Track in analytics
    Analytics.track("tenant_created", { tenant: tenant })
  end
end
```

### Validation Before Create

```ruby
BetterTenant.configure do |config|
  config.before_create do |tenant|
    # Validate tenant name format
    unless tenant.match?(/\A[a-z][a-z0-9_]*\z/)
      raise BetterTenant::Errors::ConfigurationError,
        "Invalid tenant name format: #{tenant}"
    end

    # Check against reserved names
    reserved = %w[admin api www public shared]
    if reserved.include?(tenant)
      raise BetterTenant::Errors::ConfigurationError,
        "Reserved tenant name: #{tenant}"
    end
  end
end
```

### Performance Monitoring

```ruby
BetterTenant.configure do |config|
  config.before_switch do |from, to|
    Thread.current[:tenant_switch_start] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  config.after_switch do |from, to|
    start = Thread.current[:tenant_switch_start]
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    StatsD.measure("tenant.switch.duration", duration)
    StatsD.increment("tenant.switch.count", tags: ["to:#{to || 'public'}"])

    if duration > 0.1  # 100ms
      Rails.logger.warn "Slow tenant switch: #{duration.round(3)}s"
    end
  end
end
```

### Connection Pool Management

```ruby
BetterTenant.configure do |config|
  config.before_switch do |from, to|
    # Clear connection pool before switching
    # (useful for certain database setups)
    ActiveRecord::Base.clear_active_connections!
  end
end
```

## Callback Order

```
Tenant.create("new_tenant")
  │
  ├── before_create(tenant)
  │
  ├── CREATE SCHEMA new_tenant
  │
  ├── switch to new_tenant
  │   ├── before_switch(nil, "new_tenant")
  │   ├── SET search_path TO new_tenant
  │   └── after_switch(nil, "new_tenant")
  │
  ├── after_create(tenant)  [in tenant context]
  │
  └── reset to public
      ├── before_switch("new_tenant", nil)
      ├── SET search_path TO public
      └── after_switch("new_tenant", nil)
```

## Error Handling in Callbacks

### Callback Errors

Errors in callbacks propagate and can abort the operation:

```ruby
BetterTenant.configure do |config|
  config.before_create do |tenant|
    raise "Tenant creation disabled" if ENV["DISABLE_TENANT_CREATION"]
  end
end

# Will raise error, schema not created
BetterTenant::Tenant.create("new_tenant")
```

### Safe Callbacks

Wrap non-critical code in error handling:

```ruby
BetterTenant.configure do |config|
  config.after_switch do |from, to|
    begin
      Analytics.track("tenant_switch", { tenant: to })
    rescue => e
      Rails.logger.error "Analytics error: #{e.message}"
      # Don't re-raise, allow switch to complete
    end
  end
end
```

## Testing Callbacks

```ruby
describe "Tenant callbacks" do
  before do
    @created_tenants = []
    @switches = []

    BetterTenant.configure do |config|
      config.strategy :column
      config.tenant_names %w[test]

      config.after_create { |t| @created_tenants << t }
      config.after_switch { |f, t| @switches << [f, t] }
    end
  end

  it "calls after_create callback" do
    BetterTenant::Tenant.create("test")
    expect(@created_tenants).to include("test")
  end

  it "calls after_switch callback" do
    BetterTenant::Tenant.switch("test") { }
    expect(@switches).to include([nil, "test"])
    expect(@switches).to include(["test", nil])
  end
end
```

## Best Practices

1. **Keep callbacks fast** - Avoid slow operations in switch callbacks
2. **Handle errors appropriately** - Critical code should re-raise, analytics can swallow
3. **Use after_create for seeding** - Runs in tenant context
4. **Log important events** - Helps debugging tenant issues
5. **Test callbacks** - Verify they're called with correct arguments
