# Schema Strategy

Complete guide for using the PostgreSQL schema-based multi-tenancy strategy.

---

## Overview

The schema strategy uses PostgreSQL schemas to provide database-level isolation. Each tenant has its own schema with separate tables, achieved by setting `search_path`.

### When to Use

- Strong data isolation required
- PostgreSQL as database
- Large datasets per tenant
- Per-tenant backup/restore needs
- Compliance requirements

### How It Works

1. Each tenant has a PostgreSQL schema (e.g., `acme`, `globex`)
2. BetterTenant sets `SET search_path TO acme, public` when switching
3. All queries automatically target the tenant's schema
4. Excluded models remain in `public` schema

## Basic Setup

### 1. Configuration

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names %w[acme globex initech]
  config.excluded_models %w[User Organization]
end
```

### 2. Create Schemas

```ruby
# In Rails console or migration
BetterTenant::Tenant.create("acme")
BetterTenant::Tenant.create("globex")
BetterTenant::Tenant.create("initech")
```

Or via rake task:

```bash
rake better_tenant:create[acme]
rake better_tenant:create[globex]
rake better_tenant:create[initech]
```

### 3. Excluded Models

Models that stay in `public` schema:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  # No tenant extension needed
  # Always in public schema
end

# app/models/organization.rb
class Organization < ApplicationRecord
  # No tenant extension needed
  # Always in public schema
end
```

### 4. Tenanted Models

Regular models work automatically:

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  # No special setup needed for schema strategy
  # Automatically uses current tenant's schema
end
```

## Usage

### Switching Tenants

```ruby
# Block-based (recommended)
BetterTenant::Tenant.switch("acme") do
  Article.all  # FROM acme.articles
  Article.create!(title: "Hello")  # INSERT INTO acme.articles
end

# Permanent switch
BetterTenant::Tenant.switch!("acme")
Article.all  # FROM acme.articles

# Reset to public
BetterTenant::Tenant.reset
```

### Schema Isolation

```ruby
BetterTenant::Tenant.switch("acme") do
  Article.create!(title: "Acme Article")
end

BetterTenant::Tenant.switch("globex") do
  Article.create!(title: "Globex Article")
end

# Each tenant only sees their data
BetterTenant::Tenant.switch("acme") do
  Article.count  # => 1 (only Acme's article)
end
```

### Tenant Management

```ruby
# Create a new tenant (creates schema)
BetterTenant::Tenant.create("new_tenant")

# Check if tenant exists
BetterTenant::Tenant.exists?("acme")  # => true

# Drop a tenant (drops schema CASCADE)
BetterTenant::Tenant.drop("old_tenant")

# List all tenants
BetterTenant::Tenant.tenant_names
# => ["acme", "globex", "initech"]
```

### Cross-Tenant Operations

```ruby
# Iterate over all tenants
BetterTenant::Tenant.each do |tenant|
  puts "#{tenant}: #{Article.count} articles"
end

# Access excluded models from any context
User.all  # Always from public schema
Organization.find(1)  # Always from public schema
```

## Advanced Configuration

### Schema Naming Format

Customize schema names:

```ruby
BetterTenant.configure do |config|
  config.strategy :schema
  config.schema_format "tenant_%{tenant}"
end

# "acme" -> schema "tenant_acme"
# "globex" -> schema "tenant_globex"
```

### Persistent Schemas

Schemas always in search_path:

```ruby
BetterTenant.configure do |config|
  config.strategy :schema
  config.persistent_schemas %w[shared extensions]
end

# search_path = "acme, shared, extensions, public"
```

Use case: Shared lookup tables or PostgreSQL extensions.

### Dynamic Tenant Names

```ruby
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names -> { Organization.pluck(:schema_name) }
  config.excluded_models %w[Organization]
end
```

### Using tenant_model

```ruby
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_model "Organization"
  config.tenant_identifier :subdomain
end

# Automatically:
# - tenant_names = -> { Organization.pluck(:subdomain).map(&:to_s) }
# - excluded_models includes "Organization"
```

## Migrations

### Running Migrations

Migrations run in each tenant schema:

```bash
# Migrate all tenants
rake better_tenant:migrate

# Or manually
BetterTenant::Tenant.each do |tenant|
  puts "Migrating #{tenant}..."
  # Migrations run automatically in tenant context
end
```

### Migration Best Practices

```ruby
# db/migrate/xxx_create_articles.rb
class CreateArticles < ActiveRecord::Migration[8.1]
  def change
    # This migration runs in each tenant schema
    create_table :articles do |t|
      t.string :title
      t.text :content
      t.timestamps
    end
  end
end
```

### Public Schema Migrations

For excluded models:

```ruby
# db/migrate/xxx_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # Force public schema
    execute "SET search_path TO public"

    create_table :users do |t|
      t.string :email
      t.string :name
      t.timestamps
    end

    # Reset search_path
    execute "RESET search_path"
  end
end
```

## Callbacks

### Seeding After Creation

```ruby
BetterTenant.configure do |config|
  config.strategy :schema

  config.after_create do |tenant|
    # Runs in tenant context
    Category.create!(name: "General")
    Setting.create!(key: "theme", value: "default")
  end
end
```

### Logging Switches

```ruby
BetterTenant.configure do |config|
  config.before_switch do |from, to|
    Rails.logger.info "[Tenant] Switching #{from} -> #{to}"
  end
end
```

## Performance Considerations

### Connection Pooling

Each schema switch executes `SET search_path`. Consider:

```ruby
# config/database.yml
production:
  pool: 25  # Increase pool size for high concurrency
  prepared_statements: false  # May help with schema switching
```

### Index Strategy

Indexes are per-schema (per-table), so:

- Each tenant has its own indexes
- Index bloat is isolated per tenant
- VACUUM/ANALYZE per tenant schema

### Query Performance

```sql
-- Check current search_path
SHOW search_path;
-- => "acme, public"

-- Queries resolve tables through search_path
SELECT * FROM articles;
-- Looks in: acme.articles, then public.articles
```

## Common Issues

### Schema Does Not Exist

```ruby
# Error: PG::InvalidSchemaName: schema "acme" does not exist
# Solution: Create the schema

BetterTenant::Tenant.create("acme")
```

### Tables Not Found in Schema

```ruby
# Error: PG::UndefinedTable: relation "articles" does not exist
# Solution: Run migrations for tenant

rake better_tenant:migrate
```

### Permission Denied

```sql
-- PostgreSQL user needs schema privileges
GRANT ALL ON SCHEMA acme TO app_user;
GRANT ALL ON ALL TABLES IN SCHEMA acme TO app_user;
```

### Search Path Not Set

```ruby
# Check current search_path
ActiveRecord::Base.connection.execute("SHOW search_path").first
# => {"search_path"=>"acme, public"}

# If wrong, check tenant is switched
BetterTenant::Tenant.current
```

## Database Inspection

### List All Schemas

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast');
```

### Check Schema Tables

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'acme';
```

### Verify Current Search Path

```sql
SHOW search_path;
```

## Backup & Restore

### Per-Tenant Backup

```bash
# Dump single tenant schema
pg_dump -n acme mydb > acme_backup.sql

# Dump all tenant schemas
for tenant in acme globex initech; do
  pg_dump -n $tenant mydb > ${tenant}_backup.sql
done
```

### Restore Tenant

```bash
# Restore tenant schema
psql mydb < acme_backup.sql
```
