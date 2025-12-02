# Generators - Quick Reference

Rails generators for BetterTenant setup.

---

## Install Generator

```bash
rails generate better_tenant:install [options]
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--strategy` | `column` | `:column` or `:schema` |
| `--migration` | `false` | Generate migration |
| `--table` | `nil` | Table for migration |
| `--tenant_column` | `tenant_id` | Column name |

---

## Examples

### Column Strategy (Default)

```bash
rails g better_tenant:install
```

Creates: `config/initializers/better_tenant.rb`

### Column with Migration

```bash
rails g better_tenant:install --migration --table=articles
```

Creates:
- `config/initializers/better_tenant.rb`
- `db/migrate/*_add_tenant_id_to_articles.rb`

### Schema Strategy

```bash
rails g better_tenant:install --strategy=schema
```

### Custom Column Name

```bash
rails g better_tenant:install --migration --table=posts --tenant_column=organization_id
```

---

## Generated Files

### Initializer

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names []
  config.excluded_models []
  config.require_tenant false
  config.strict_mode false
end
```

### Migration

```ruby
class AddTenantIdToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :tenant_id, :string
    add_index :articles, :tenant_id
  end
end
```

---

## Post-Install Steps

1. Edit `config/initializers/better_tenant.rb`
2. Uncomment middleware in `config/application.rb`
3. Add `include BetterTenant::ActiveRecordExtension` to models
4. Run `rails db:migrate` if migration generated
