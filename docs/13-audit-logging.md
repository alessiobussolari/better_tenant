# Audit Logging

Logging and monitoring tenant operations with BetterTenant.

---

## Overview

BetterTenant provides built-in audit logging through the `AuditLogger` class. This feature helps you:

- Track tenant switches for debugging
- Monitor access patterns
- Detect and log policy violations
- Log errors with tenant context

## Configuration

Enable audit logging in your initializer:

```ruby
BetterTenant.configure do |config|
  # Log all tenant access (switches, queries)
  config.audit_access true

  # Log policy violations (cross-tenant access, immutable changes)
  config.audit_violations true
end
```

| Option | Default | Description |
|--------|---------|-------------|
| `audit_access` | `false` | Log all tenant switches and access |
| `audit_violations` | `false` | Log tenant policy violations |

---

## Log Types

### Switch Logs

Logged when tenant context changes:

```ruby
config.audit_access true
```

**Output:**

```
[BetterTenant] Tenant switch: from=nil to=acme timestamp=2024-01-15T10:30:00Z
[BetterTenant] Tenant switch: from=acme to=globex timestamp=2024-01-15T10:31:00Z
[BetterTenant] Tenant switch: from=globex to=nil timestamp=2024-01-15T10:32:00Z
```

### Access Logs

Logged for tenant-scoped operations:

```ruby
config.audit_access true
```

**Output:**

```
[BetterTenant] Tenant access: tenant=acme model=Article operation=query timestamp=2024-01-15T10:30:05Z
[BetterTenant] Tenant access: tenant=acme model=Article operation=create timestamp=2024-01-15T10:30:10Z
[BetterTenant] Tenant access: tenant=acme model=Comment operation=update timestamp=2024-01-15T10:30:15Z
```

### Violation Logs

Logged when tenant policies are violated:

```ruby
config.audit_violations true
```

**Output:**

```
[BetterTenant] Tenant violation: type=cross_tenant_access tenant=acme model=Article details=attempted_access_to_globex timestamp=2024-01-15T10:30:00Z
[BetterTenant] Tenant violation: type=immutable_tenant tenant=acme model=Article details=tenant_id_change_attempted timestamp=2024-01-15T10:31:00Z
[BetterTenant] Tenant violation: type=missing_context tenant=nil model=Article details=query_without_tenant timestamp=2024-01-15T10:32:00Z
```

### Error Logs

Logged when tenant-related errors occur:

```
[BetterTenant] Tenant error: error_class=BetterTenant::Errors::TenantNotFoundError message=Tenant 'invalid' not found tenant=nil model=nil timestamp=2024-01-15T10:30:00Z backtrace=app/controllers/articles_controller.rb:15 | app/middleware/tenant_middleware.rb:23 | ...
```

---

## AuditLogger API

### log_switch

Logs tenant switch events.

```ruby
BetterTenant::AuditLogger.log_switch(from_tenant, to_tenant)
```

**Parameters:**
- `from` - Previous tenant (String or nil)
- `to` - New tenant (String or nil)

**Example:**

```ruby
BetterTenant::AuditLogger.log_switch("acme", "globex")
# [BetterTenant] Tenant switch: from=acme to=globex timestamp=2024-01-15T10:30:00Z
```

### log_access

Logs tenant access events.

```ruby
BetterTenant::AuditLogger.log_access(tenant, model, operation)
```

**Parameters:**
- `tenant` - Current tenant (String)
- `model` - Model class name (String)
- `operation` - Operation type (String): "query", "create", "update", "delete"

**Example:**

```ruby
BetterTenant::AuditLogger.log_access("acme", "Article", "create")
# [BetterTenant] Tenant access: tenant=acme model=Article operation=create timestamp=2024-01-15T10:30:00Z
```

### log_violation

Logs tenant policy violations.

```ruby
BetterTenant::AuditLogger.log_violation(
  type: :violation_type,
  tenant: "tenant_name",
  model: "ModelName",
  details: "additional info"
)
```

**Parameters:**
- `type` - Violation type (Symbol): `:cross_tenant_access`, `:immutable_tenant`, `:missing_context`
- `tenant` - Current tenant (String)
- `model` - Model class name (String)
- `details` - Additional details (String, optional)

**Example:**

```ruby
BetterTenant::AuditLogger.log_violation(
  type: :cross_tenant_access,
  tenant: "acme",
  model: "Article",
  details: "attempted_access_to_record_id_123"
)
# [BetterTenant] Tenant violation: type=cross_tenant_access tenant=acme model=Article details=attempted_access_to_record_id_123 timestamp=2024-01-15T10:30:00Z
```

### log_error

Logs tenant-related errors with backtrace.

```ruby
BetterTenant::AuditLogger.log_error(error, tenant: "tenant_name", model: "ModelName")
```

**Parameters:**
- `error` - Exception object
- `tenant` - Current tenant (String)
- `model` - Model class name (String, optional)

**Example:**

```ruby
begin
  # some operation
rescue => e
  BetterTenant::AuditLogger.log_error(e, tenant: "acme", model: "Article")
end
# [BetterTenant] Tenant error: error_class=StandardError message=Something went wrong tenant=acme model=Article timestamp=2024-01-15T10:30:00Z backtrace=...
```

---

## Log Format

All logs follow this format:

```
[BetterTenant] PREFIX: key=value key=value ...
```

**Example breakdown:**

```
[BetterTenant] Tenant switch: from=acme to=globex timestamp=2024-01-15T10:30:00Z
│             │               │        │        │
│             │               │        │        └── ISO8601 timestamp
│             │               │        └── New tenant
│             │               └── Previous tenant
│             └── Log type
└── Gem prefix
```

---

## Sentry Integration

BetterTenant error classes include Sentry-compatible methods for rich error reporting.

### Error Class Methods

Each error class provides:

```ruby
class TenantNotFoundError < TenantError
  def tags
    { tenant_error_type: "not_found" }
  end

  def context
    { tenant_name: @tenant_name }
  end

  def extra
    { searched_tenants: BetterTenant::Tenant.tenant_names }
  end
end
```

### Sentry Configuration

Configure Sentry to use these methods:

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  config.before_send = lambda do |event, hint|
    exception = hint[:exception]

    if exception.respond_to?(:tags)
      event.tags.merge!(exception.tags)
    end

    if exception.respond_to?(:context)
      event.contexts[:tenant] = exception.context
    end

    if exception.respond_to?(:extra)
      event.extra.merge!(exception.extra)
    end

    event
  end
end
```

### Error Classes with Sentry Support

| Error Class | Tags | Context | Extra |
|-------------|------|---------|-------|
| `TenantNotFoundError` | `tenant_error_type: "not_found"` | `tenant_name` | `searched_tenants` |
| `TenantContextMissingError` | `tenant_error_type: "missing_context"` | `operation`, `model_class` | - |
| `TenantImmutableError` | `tenant_error_type: "immutable"` | `tenant_column`, `model_class`, `record_id` | - |
| `TenantMismatchError` | `tenant_error_type: "mismatch"` | `expected_tenant_id`, `actual_tenant_id`, `operation`, `model_class` | - |
| `SchemaNotFoundError` | `tenant_error_type: "schema_not_found"` | `schema_name`, `tenant_name` | - |

---

## Custom Logging

### Use Your Own Logger

By default, AuditLogger uses `Rails.logger`. For custom logging:

```ruby
# Create a custom audit logger
module MyApp
  class TenantAuditLogger
    def self.log_switch(from, to)
      MyCustomLogger.info(
        event: "tenant_switch",
        from: from,
        to: to,
        timestamp: Time.current
      )
    end

    def self.log_violation(type:, tenant:, model:, details: nil)
      MyCustomLogger.warn(
        event: "tenant_violation",
        type: type,
        tenant: tenant,
        model: model,
        details: details
      )
    end
  end
end
```

### Log to External Services

Send audit logs to external services:

```ruby
BetterTenant.configure do |config|
  config.after_switch do |from, to|
    # Send to analytics
    Analytics.track("tenant_switch", {
      from: from,
      to: to,
      user_id: Current.user&.id
    })

    # Send to audit service
    AuditService.log(
      action: "tenant_switch",
      actor: Current.user&.email,
      tenant_from: from,
      tenant_to: to
    )
  end
end
```

### Structured Logging

For JSON-structured logs:

```ruby
# config/initializers/better_tenant_logging.rb
module BetterTenantStructuredLogging
  def self.setup
    BetterTenant.configure do |config|
      config.after_switch do |from, to|
        Rails.logger.info({
          event: "tenant.switch",
          from_tenant: from,
          to_tenant: to,
          request_id: Current.request_id,
          user_id: Current.user&.id,
          timestamp: Time.current.iso8601
        }.to_json)
      end
    end
  end
end

BetterTenantStructuredLogging.setup
```

---

## Performance Monitoring

### Track Switch Duration

```ruby
BetterTenant.configure do |config|
  config.before_switch do |from, to|
    Thread.current[:tenant_switch_start] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  config.after_switch do |from, to|
    start = Thread.current[:tenant_switch_start]
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    # Send to StatsD/Datadog
    StatsD.timing("tenant.switch.duration", duration * 1000)
    StatsD.increment("tenant.switch.count", tags: ["to:#{to || 'public'}"])

    # Log slow switches
    if duration > 0.1  # 100ms
      Rails.logger.warn "[BetterTenant] Slow switch: #{(duration * 1000).round}ms"
    end
  end
end
```

### Track Tenant Usage

```ruby
BetterTenant.configure do |config|
  config.after_switch do |from, to|
    next unless to

    # Increment tenant usage counter
    Redis.current.incr("tenant:#{to}:switches")
    Redis.current.sadd("active_tenants:#{Date.current}", to)
  end
end
```

---

## Best Practices

1. **Enable audit_violations in production** - Helps detect security issues
2. **Use audit_access sparingly** - Can generate many logs, use in development/staging
3. **Integrate with Sentry** - Get rich error context automatically
4. **Use structured logging** - Easier to parse and analyze
5. **Monitor switch duration** - Detect performance issues early
6. **Set up alerts** - Notify on violation patterns

```ruby
# Example: Alert on too many violations
BetterTenant.configure do |config|
  config.audit_violations true

  # Custom violation handler
  Thread.current[:violation_count] ||= 0

  # In your application
  def handle_violation(type, tenant, model)
    Thread.current[:violation_count] += 1

    if Thread.current[:violation_count] > 10
      AlertService.notify("High tenant violation rate", {
        tenant: tenant,
        count: Thread.current[:violation_count]
      })
    end
  end
end
```
