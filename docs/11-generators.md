# Generators

Rails generators for setting up BetterTenant in your application.

---

## Overview

BetterTenant provides a Rails generator to quickly set up multi-tenancy in your application. The generator creates configuration files and optionally generates migrations.

## Installation Generator

### Basic Usage

```bash
rails generate better_tenant:install
```

This creates the basic configuration with column strategy (default).

### Available Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--strategy` | String | `column` | Tenancy strategy: `column` or `schema` |
| `--migration` | Boolean | `false` | Generate migration for tenant_id column |
| `--table` | String | `nil` | Table name for tenant_id migration |
| `--tenant_column` | String | `tenant_id` | Name of the tenant column |

---

## Usage Examples

### Column Strategy (Default)

```bash
rails generate better_tenant:install
```

**Generated files:**

1. `config/initializers/better_tenant.rb`:

```ruby
# frozen_string_literal: true

# BetterTenant Configuration
#
# This initializer configures multi-tenancy for your Rails application.
#
BetterTenant.configure do |config|
  # Strategy: :schema (PostgreSQL schemas) or :column (shared database with tenant_id)
  config.strategy :column

  # The column name used to identify the tenant
  config.tenant_column :tenant_id

  # List of tenant names (can be an array or a Proc/Lambda)
  # Static list:
  # config.tenant_names %w[acme globex initech]
  #
  # Dynamic list from database:
  # config.tenant_names -> { Tenant.pluck(:subdomain) }
  config.tenant_names []

  # Models excluded from tenancy (shared across all tenants)
  # config.excluded_models %w[User Tenant Plan]
  config.excluded_models []

  # Require tenant context for all operations
  # When true, raises TenantContextMissingError if no tenant is set
  config.require_tenant false

  # Strict mode prevents changing tenant_id on existing records
  config.strict_mode false

  # Excluded subdomains (for subdomain elevator)
  config.excluded_subdomains %w[www admin api]

  # Excluded paths (for path elevator)
  config.excluded_paths %w[api admin assets]

  # Callbacks for tenant lifecycle events
  # config.before_create { |tenant| Rails.logger.info "Creating tenant: #{tenant}" }
  # config.after_create { |tenant| Rails.logger.info "Created tenant: #{tenant}" }
  # config.before_switch { |from, to| Rails.logger.info "Switching from #{from} to #{to}" }
  # config.after_switch { |from, to| Rails.logger.info "Switched to #{to}" }
end
```

2. Comments added to `config/application.rb`:

```ruby
class Application < Rails::Application
    # BetterTenant middleware for automatic tenant switching
    # Uncomment and configure the elevator type as needed:
    # config.middleware.use BetterTenant::Middleware, :subdomain
    # config.middleware.use BetterTenant::Middleware, :header
    # config.middleware.use BetterTenant::Middleware, :path
    # config.middleware.use BetterTenant::Middleware, ->(request) { request.host.split('.').first }

    # ... rest of config
end
```

---

### Column Strategy with Migration

```bash
rails generate better_tenant:install --strategy=column --migration --table=articles
```

**Additional generated file:**

`db/migrate/YYYYMMDDHHMMSS_add_tenant_id_to_articles.rb`:

```ruby
# frozen_string_literal: true

class AddTenantIdToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :tenant_id, :string
    add_index :articles, :tenant_id
  end
end
```

---

### Column Strategy with Custom Column Name

```bash
rails generate better_tenant:install --migration --table=posts --tenant_column=organization_id
```

**Generated migration:**

```ruby
class AddOrganizationIdToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :organization_id, :string
    add_index :posts, :organization_id
  end
end
```

**Generated initializer** (excerpt):

```ruby
config.tenant_column :organization_id
```

---

### Schema Strategy

```bash
rails generate better_tenant:install --strategy=schema
```

**Generated initializer:**

```ruby
BetterTenant.configure do |config|
  # Strategy: :schema (PostgreSQL schemas) or :column (shared database with tenant_id)
  config.strategy :schema

  # List of tenant names (can be an array or a Proc/Lambda)
  config.tenant_names []

  # Models excluded from tenancy (shared across all tenants)
  config.excluded_models []

  # Schemas that should always be in the search_path
  config.persistent_schemas %w[shared public]

  # Schema naming format (%{tenant} is replaced with tenant name)
  config.schema_format "tenant_%{tenant}"

  # Require tenant context for all operations
  config.require_tenant false

  # Strict mode prevents changing tenant_id on existing records
  config.strict_mode false

  # Excluded subdomains (for subdomain elevator)
  config.excluded_subdomains %w[www admin api]

  # Excluded paths (for path elevator)
  config.excluded_paths %w[api admin assets]

  # Callbacks for tenant lifecycle events
  # config.before_create { |tenant| Rails.logger.info "Creating tenant: #{tenant}" }
  # config.after_create { |tenant| Rails.logger.info "Created tenant: #{tenant}" }
end
```

---

## Post-Installation Steps

After running the generator, the following message is displayed:

```
BetterTenant has been installed!

Next steps:
  1. Edit config/initializers/better_tenant.rb to configure your tenants
  2. Uncomment the middleware line in config/application.rb
  3. Include BetterTenant::ActiveRecordExtension in your models

Example model setup:
  class Article < ApplicationRecord
    include BetterTenant::ActiveRecordExtension
  end
```

### Step 1: Configure Tenants

Edit `config/initializers/better_tenant.rb`:

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_names %w[acme globex initech]
  # Or dynamically:
  # config.tenant_names -> { Organization.pluck(:subdomain) }
end
```

### Step 2: Enable Middleware

Uncomment the middleware in `config/application.rb`:

```ruby
config.middleware.use BetterTenant::Middleware, :subdomain
```

### Step 3: Add Extension to Models

```ruby
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end
```

### Step 4: Run Migration (if generated)

```bash
rails db:migrate
```

---

## Multiple Table Migrations

The generator only creates one migration at a time. For multiple tables, run the generator multiple times or create migrations manually:

```bash
# Generate for first table
rails generate better_tenant:install --migration --table=articles

# Generate additional migrations manually
rails generate migration AddTenantIdToPosts tenant_id:string:index
rails generate migration AddTenantIdToComments tenant_id:string:index
```

Or create a single migration for multiple tables:

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_tenant_id_to_all_tables.rb
class AddTenantIdToAllTables < ActiveRecord::Migration[8.1]
  TENANT_TABLES = %i[articles posts comments categories tags]

  def change
    TENANT_TABLES.each do |table|
      add_column table, :tenant_id, :string
      add_index table, :tenant_id
    end
  end
end
```

---

## Customizing Templates

If you need to customize the generated files, you can override the templates:

### 1. Copy Templates to Your App

```bash
mkdir -p lib/templates/better_tenant/install
cp $(bundle show better_tenant)/lib/generators/better_tenant/templates/* lib/templates/better_tenant/install/
```

### 2. Modify Templates

Edit the files in `lib/templates/better_tenant/install/`:

- `initializer.rb.tt` - Configuration file template
- `add_tenant_id_migration.rb.tt` - Migration template

### 3. Template Variables

Available variables in templates:

| Variable | Description |
|----------|-------------|
| `<%= strategy %>` | Selected strategy (`column` or `schema`) |
| `<%= tenant_column %>` | Tenant column name |
| `<%= table_name %>` | Target table name (migrations) |

---

## Troubleshooting

### Generator Not Found

```
Could not find generator 'better_tenant:install'
```

**Solution:** Ensure the gem is installed and bundled:

```bash
bundle install
```

### Migration Table Not Specified

```
# No migration generated
```

**Solution:** When using `--migration`, also specify `--table`:

```bash
rails generate better_tenant:install --migration --table=your_table
```

### Wrong Rails Version in Migration

If the migration shows an incorrect Rails version:

**Solution:** Edit the generated migration to use the correct version:

```ruby
class AddTenantIdToArticles < ActiveRecord::Migration[8.1]
  # ...
end
```

---

## Generator Source

The generator is located at:

```
lib/generators/better_tenant/install_generator.rb
lib/generators/better_tenant/templates/
  ├── initializer.rb.tt
  └── add_tenant_id_migration.rb.tt
```
