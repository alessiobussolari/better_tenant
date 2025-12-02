# Configuration

Configuration options for BetterTenant.

---

## Generate Initializer

```bash
rails generate better_tenant:install
```

--------------------------------

## Default Configuration

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names %w[acme globex]
end
```

--------------------------------

## All Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `strategy` | `Symbol` | `:column` | `:column` or `:schema` |
| `tenant_column` | `Symbol` | `:tenant_id` | Column for filtering |
| `tenant_names` | `Array/Proc` | `[]` | Valid tenant names |
| `tenant_model` | `String` | `nil` | Model for dynamic names |
| `tenant_identifier` | `Symbol` | `:id` | Model identifier column |
| `excluded_models` | `Array` | `[]` | Non-tenant models |
| `persistent_schemas` | `Array` | `[]` | Always in search_path |
| `schema_format` | `String` | `"%{tenant}"` | Schema naming |
| `elevator` | `Symbol/Proc` | `nil` | Tenant detection |
| `require_tenant` | `Boolean` | `true` | Require tenant context |
| `strict_mode` | `Boolean` | `false` | Prevent tenant_id change |

--------------------------------

## Dynamic Tenant Names

```ruby
config.tenant_names -> { Organization.pluck(:slug) }
```

--------------------------------

## Tenant Model

```ruby
config.tenant_model "Organization"
config.tenant_identifier :slug
# Auto-creates: tenant_names -> { Organization.pluck(:slug) }
# Auto-excludes: Organization from tenancy
```

--------------------------------

## Callbacks

```ruby
config.before_create { |tenant| }
config.after_create { |tenant| }
config.before_switch { |from, to| }
config.after_switch { |from, to| }
```

--------------------------------
