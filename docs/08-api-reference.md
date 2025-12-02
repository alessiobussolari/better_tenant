# API Reference

Complete API reference for BetterTenant.

---

## Main Module

### `BetterTenant`

The main module that provides configuration and access to tenant functionality.

#### Methods

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `.configure` | `&block` | `void` | Configure BetterTenant with a block |
| `.configuration` | none | `Hash` | Get current configuration hash |
| `.reset!` | none | `void` | Reset configuration (for testing) |

#### Examples

```ruby
# Configure
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
end

# Access configuration
BetterTenant.configuration
# => {:strategy=>:column, :tenant_column=>:tenant_id, ...}

# Reset (testing)
BetterTenant.reset!
```

---

## Core Classes

### `BetterTenant::Tenant`

The main API for tenant operations.

#### Class Methods

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `.current` | none | `String/nil` | Get current tenant name |
| `.switch!` | `tenant` | `String` | Switch tenant permanently |
| `.switch` | `tenant, &block` | `Object` | Switch tenant for block duration |
| `.reset` | none | `void` | Reset to default (public) |
| `.create` | `tenant` | `void` | Create a new tenant |
| `.drop` | `tenant` | `void` | Drop a tenant |
| `.exists?` | `tenant` | `Boolean` | Check if tenant exists |
| `.tenant_names` | none | `Array<String>` | Get all tenant names |
| `.each` | `&block` | `void` | Iterate over all tenants |
| `.excluded_model?` | `model_name` | `Boolean` | Check if model is excluded |
| `.adapter` | none | `AbstractAdapter` | Get the adapter instance |
| `.configuration` | none | `Hash` | Get configuration hash |
| `.reset!` | none | `void` | Reset state (testing) |

#### Examples

```ruby
# Get current tenant
BetterTenant::Tenant.current
# => "acme" or nil

# Switch for block
BetterTenant::Tenant.switch("acme") do
  Article.all
end

# Permanent switch
BetterTenant::Tenant.switch!("acme")

# Reset
BetterTenant::Tenant.reset

# Create tenant (schema strategy)
BetterTenant::Tenant.create("new_tenant")

# Drop tenant (schema strategy)
BetterTenant::Tenant.drop("old_tenant")

# Check existence
BetterTenant::Tenant.exists?("acme")
# => true

# List all
BetterTenant::Tenant.tenant_names
# => ["acme", "globex", "initech"]

# Iterate
BetterTenant::Tenant.each do |tenant|
  puts "#{tenant}: #{Article.count}"
end

# Check excluded
BetterTenant::Tenant.excluded_model?("User")
# => true/false
```

---

### `BetterTenant::Configurator`

Configuration builder passed to configure block.

#### Methods

| Method | Arguments | Description |
|--------|-----------|-------------|
| `strategy` | `value` | Set strategy (`:column` or `:schema`) |
| `tenant_column` | `value` | Set tenant column name |
| `tenant_names` | `value` | Set tenant names (Array or Proc) |
| `tenant_model` | `value` | Set tenant model class name |
| `tenant_identifier` | `value` | Set tenant identifier column |
| `excluded_models` | `value` | Set excluded model names |
| `persistent_schemas` | `value` | Set persistent schemas |
| `schema_format` | `value` | Set schema naming format |
| `elevator` | `value` | Set elevator type or Proc |
| `excluded_subdomains` | `value` | Set excluded subdomains |
| `excluded_paths` | `value` | Set excluded paths |
| `require_tenant` | `value` | Set require tenant flag |
| `strict_mode` | `value` | Set strict mode flag |
| `audit_violations` | `value` | Set audit violations flag |
| `audit_access` | `value` | Set audit access flag |
| `before_create` | `&block` | Register before_create callback |
| `after_create` | `&block` | Register after_create callback |
| `before_switch` | `&block` | Register before_switch callback |
| `after_switch` | `&block` | Register after_switch callback |

#### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `VALID_STRATEGIES` | `[:column, :schema]` | Valid strategy values |
| `VALID_ELEVATORS` | `[:subdomain, :domain, :header, :generic, :host, :path]` | Valid elevator types |

---

### `BetterTenant::Middleware`

Rack middleware for automatic tenant switching.

#### Constructor

```ruby
BetterTenant::Middleware.new(app, elevator = :subdomain)
```

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `app` | `Rack app` | required | The Rack application |
| `elevator` | `Symbol/Proc` | `:subdomain` | Elevator type or custom Proc |

#### Elevators

| Type | Detection Method |
|------|-----------------|
| `:subdomain` | `acme.example.com` -> `"acme"` |
| `:domain` | Full domain as tenant |
| `:header` | `X-Tenant` header value |
| `:path` | `/acme/articles` -> `"acme"` |
| `Proc` | Custom extraction logic |

#### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DEFAULT_EXCLUDED_SUBDOMAINS` | `["www"]` | Default excluded subdomains |
| `DEFAULT_EXCLUDED_PATHS` | `["api", "admin", ...]` | Default excluded paths |
| `DEFAULT_TENANT_HEADER` | `"HTTP_X_TENANT"` | Header env key |

---

### `BetterTenant::ActiveRecordExtension`

Module to include in tenanted ActiveRecord models.

#### Class Methods (added to including class)

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `.tenantable?` | none | `Boolean` | Check if model is tenantable |
| `.excluded_from_tenancy?` | none | `Boolean` | Check if excluded from tenancy |
| `.tenant_column` | none | `Symbol` | Get tenant column name |
| `.current_tenant` | none | `String/nil` | Get current tenant |
| `.unscoped_tenant` | `&block` | `Object` | Execute without tenant scope |
| `.column_strategy?` | none | `Boolean` | Check if using column strategy |
| `.require_tenant?` | none | `Boolean` | Check if tenant is required |

#### Example

```ruby
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end

Article.tenantable?           # => true
Article.excluded_from_tenancy? # => false
Article.tenant_column         # => :tenant_id
Article.current_tenant        # => "acme" or nil

Article.unscoped_tenant do
  Article.count  # All articles
end
```

---

### `BetterTenant::ActiveJobExtension`

Module to include in jobs for tenant context preservation.

#### Instance Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `tenant_for_job` | `String/nil` | Captured tenant name |

#### Methods

| Method | Description |
|--------|-------------|
| `serialize` | Includes tenant in job data |
| `deserialize` | Restores tenant from job data |

#### Example

```ruby
class MyJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(id)
    # Automatically in correct tenant context
    Model.find(id)
  end
end
```

---

## Adapters

### `BetterTenant::Adapters::AbstractAdapter`

Base class for tenant adapters.

#### Methods

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `current` | none | `String/nil` | Get current tenant |
| `switch!` | `tenant` | `String` | Switch permanently |
| `switch` | `tenant, &block` | `Object` | Switch for block |
| `reset` | none | `void` | Reset to default |
| `create` | `tenant` | `void` | Create tenant |
| `drop` | `tenant` | `void` | Drop tenant |
| `exists?` | `tenant` | `Boolean` | Check existence |
| `all_tenants` | none | `Array<String>` | Get all tenant names |
| `schema_for` | `tenant` | `String` | Get schema name |
| `each_tenant` | `&block` | `void` | Iterate tenants |

---

### `BetterTenant::Adapters::ColumnAdapter`

Adapter for column-based multi-tenancy.

#### Additional Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `tenant_column` | `Symbol` | Get tenant column name |

---

### `BetterTenant::Adapters::PostgresqlAdapter`

Adapter for schema-based multi-tenancy.

#### Additional Methods

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `schema_exists?` | `schema` | `Boolean` | Check if schema exists in DB |
| `current_search_path` | none | `String` | Get current search_path |
| `default_search_path` | none | `String` | Get default search_path |

---

## Errors

### `BetterTenant::Errors::TenantError`

Base class for all BetterTenant errors.

### `BetterTenant::Errors::ConfigurationError`

Raised for configuration issues.

```ruby
raise ConfigurationError, "Invalid strategy"
```

### `BetterTenant::Errors::TenantNotFoundError`

Raised when tenant doesn't exist.

```ruby
raise TenantNotFoundError.new(tenant_name: "unknown")
```

### `BetterTenant::Errors::TenantContextMissingError`

Raised when operation requires tenant but none set.

```ruby
raise TenantContextMissingError.new(
  operation: "query",
  model_class: "Article"
)
```

### `BetterTenant::Errors::TenantMismatchError`

Raised for tenant mismatch in strict mode.

### `BetterTenant::Errors::TenantImmutableError`

Raised when trying to change tenant_id in strict mode.

```ruby
raise TenantImmutableError.new(
  tenant_column: :tenant_id,
  model_class: "Article",
  record_id: 123
)
```

### `BetterTenant::Errors::SchemaNotFoundError`

Raised when PostgreSQL schema doesn't exist.

---

## Configuration Hash Structure

```ruby
{
  strategy: :column,              # :column or :schema
  tenant_column: :tenant_id,      # Column name
  tenant_names: [...],            # Array or Proc
  tenant_model: "Organization",   # Model class name
  tenant_identifier: :id,         # Identifier column
  excluded_models: [...],         # Array of model names
  persistent_schemas: [...],      # Array of schema names
  schema_format: "%{tenant}",     # Format string
  elevator: :subdomain,           # Symbol or Proc
  excluded_subdomains: [...],     # Array of strings
  excluded_paths: [...],          # Array of strings
  require_tenant: true,           # Boolean
  strict_mode: false,             # Boolean
  audit_violations: false,        # Boolean
  audit_access: false,            # Boolean
  callbacks: {                    # Callback procs
    before_create: Proc,
    after_create: Proc,
    before_switch: Proc,
    after_switch: Proc
  }
}
```
