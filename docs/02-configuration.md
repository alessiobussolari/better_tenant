# Configuration

Complete configuration options for BetterTenant.

---

## Initializer

Generate the initializer:

```bash
rails generate better_tenant:install
```

This creates `config/initializers/better_tenant.rb`.

## Default Configuration

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  # Strategy: :column (default) or :schema
  config.strategy :column

  # Tenant column name (column strategy)
  config.tenant_column :tenant_id

  # List of valid tenant names
  config.tenant_names %w[acme globex initech]

  # Or use a Proc for dynamic loading
  # config.tenant_names -> { Organization.pluck(:slug) }

  # Or use tenant_model for automatic configuration
  # config.tenant_model "Organization"
  # config.tenant_identifier :slug

  # Models excluded from tenancy
  config.excluded_models []

  # Persistent schemas (schema strategy)
  config.persistent_schemas []

  # Schema naming format (schema strategy)
  config.schema_format "%{tenant}"

  # Elevator for middleware
  config.elevator nil

  # Excluded subdomains
  config.excluded_subdomains []

  # Excluded path segments
  config.excluded_paths []

  # Require tenant context
  config.require_tenant true

  # Strict mode (prevent tenant_id changes)
  config.strict_mode false

  # Audit logging
  config.audit_violations false
  config.audit_access false
end
```

## Options Reference

### Core Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `strategy` | `Symbol` | `:column` | Isolation strategy (`:column` or `:schema`) |
| `tenant_column` | `Symbol` | `:tenant_id` | Column name for tenant filtering (column strategy) |
| `tenant_names` | `Array/Proc` | `[]` | List of valid tenant names or Proc returning them |
| `tenant_model` | `String` | `nil` | Model class to query for tenant names |
| `tenant_identifier` | `Symbol` | `:id` | Column to use as tenant identifier (with `tenant_model`) |

### Schema Strategy Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `excluded_models` | `Array` | `[]` | Model names that remain in public schema |
| `persistent_schemas` | `Array` | `[]` | Schemas always included in search_path |
| `schema_format` | `String` | `"%{tenant}"` | Schema naming template |

### Middleware Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `elevator` | `Symbol/Proc` | `nil` | Tenant detection method for middleware |
| `excluded_subdomains` | `Array` | `[]` | Subdomains to ignore (subdomain elevator) |
| `excluded_paths` | `Array` | `[]` | Path segments to ignore (path elevator) |

### Behavior Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `require_tenant` | `Boolean` | `true` | Raise error if no tenant context |
| `strict_mode` | `Boolean` | `false` | Prevent changing tenant_id on records |
| `audit_violations` | `Boolean` | `false` | Log tenant violation attempts |
| `audit_access` | `Boolean` | `false` | Log all tenant access |

## Detailed Option Descriptions

### strategy

Determines how tenant data is isolated:

```ruby
# Column strategy - uses tenant_id column
config.strategy :column

# Schema strategy - uses PostgreSQL schemas
config.strategy :schema
```

### tenant_names

Defines valid tenant names:

```ruby
# Static array
config.tenant_names %w[acme globex initech]

# Dynamic Proc (evaluated on each access)
config.tenant_names -> { Organization.pluck(:slug) }

# Lambda with custom logic
config.tenant_names -> {
  Organization.where(active: true).pluck(:subdomain)
}
```

### tenant_model

Automatically configures tenant_names and excluded_models:

```ruby
config.tenant_model "Organization"
config.tenant_identifier :slug

# Equivalent to:
# config.tenant_names -> { Organization.pluck(:slug).map(&:to_s) }
# config.excluded_models ["Organization"]
```

### excluded_models

Models that bypass tenant filtering:

```ruby
config.excluded_models %w[User Organization Admin::Setting]
```

### schema_format

Template for schema names:

```ruby
# Default: tenant name as schema name
config.schema_format "%{tenant}"
# "acme" -> schema "acme"

# Prefixed schemas
config.schema_format "tenant_%{tenant}"
# "acme" -> schema "tenant_acme"

# Custom format
config.schema_format "org_%{tenant}_data"
# "acme" -> schema "org_acme_data"
```

### persistent_schemas

Schemas always in PostgreSQL search_path:

```ruby
config.persistent_schemas %w[shared extensions]
# search_path = "tenant_acme, shared, extensions, public"
```

### elevator

Tenant detection method for middleware:

```ruby
# Built-in elevators
config.elevator :subdomain  # acme.example.com -> "acme"
config.elevator :domain     # Full domain as tenant
config.elevator :header     # X-Tenant header
config.elevator :path       # /acme/articles -> "acme"

# Custom Proc
config.elevator ->(request) {
  request.params["tenant"] || request.session[:tenant]
}
```

### require_tenant

Controls behavior when no tenant context:

```ruby
# Raise error if no tenant (default)
config.require_tenant true

# Allow operations without tenant
config.require_tenant false
```

### strict_mode

Prevents changing tenant_id after creation:

```ruby
config.strict_mode true

# With strict_mode:
article = Article.create!(title: "Test")
article.tenant_id = "other"
article.save!  # Raises TenantImmutableError
```

## Environment-Specific Configuration

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id

  if Rails.env.production?
    config.tenant_names -> { Organization.where(active: true).pluck(:slug) }
    config.require_tenant true
    config.audit_violations true
  else
    config.tenant_names %w[dev_tenant test_tenant]
    config.require_tenant false
    config.audit_violations false
  end
end
```

## Callbacks

Register callbacks for tenant lifecycle events:

```ruby
BetterTenant.configure do |config|
  # Before/after tenant creation (schema strategy)
  config.before_create do |tenant|
    Rails.logger.info "Creating tenant: #{tenant}"
  end

  config.after_create do |tenant|
    Rails.logger.info "Created tenant: #{tenant}"
    # Seed initial data
    Category.create!(name: "Default")
  end

  # Before/after tenant switch
  config.before_switch do |from, to|
    Rails.logger.info "Switching from #{from} to #{to}"
  end

  config.after_switch do |from, to|
    Rails.logger.info "Switched to #{to}"
  end
end
```

## Accessing Configuration

```ruby
# Get full configuration hash
BetterTenant.configuration
# => {:strategy=>:column, :tenant_column=>:tenant_id, ...}

# Get specific option
BetterTenant.configuration[:strategy]
# => :column

# Reset configuration (for testing)
BetterTenant.reset!
```
