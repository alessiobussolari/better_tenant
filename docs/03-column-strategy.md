# Column Strategy

Complete guide for using the column-based multi-tenancy strategy.

---

## Overview

The column strategy uses a shared database with tenant isolation via a `tenant_id` column. All tenants share the same tables, with automatic query filtering applied.

### When to Use

- Multiple databases not required
- Simple setup preferred
- Any database (not just PostgreSQL)
- Smaller datasets per tenant
- Shared migrations across tenants

### How It Works

1. Each tenant table has a `tenant_id` column
2. BetterTenant adds a default scope filtering by `tenant_id`
3. New records automatically get `tenant_id` set
4. Cross-tenant queries are prevented (unless explicitly unscoped)

## Basic Setup

### 1. Configuration

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names %w[acme globex initech]
end
```

### 2. Migration

Add tenant column to your tables:

```ruby
# db/migrate/xxx_add_tenant_id_to_tables.rb
class AddTenantIdToTables < ActiveRecord::Migration[8.1]
  def change
    # Add to each tenanted table
    add_column :articles, :tenant_id, :string
    add_column :comments, :tenant_id, :string
    add_column :products, :tenant_id, :string

    # Add indexes for performance
    add_index :articles, :tenant_id
    add_index :comments, :tenant_id
    add_index :products, :tenant_id
  end
end
```

### 3. Model Setup

Include the extension in each tenanted model:

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension

  has_many :comments
end

# app/models/comment.rb
class Comment < ApplicationRecord
  include BetterTenant::ActiveRecordExtension

  belongs_to :article
end
```

### 4. Base Model (Optional)

For cleaner setup, create a base class:

```ruby
# app/models/tenant_record.rb
class TenantRecord < ApplicationRecord
  self.abstract_class = true
  include BetterTenant::ActiveRecordExtension
end

# app/models/article.rb
class Article < TenantRecord
  has_many :comments
end
```

## Usage

### Switching Tenants

```ruby
# Block-based (recommended)
BetterTenant::Tenant.switch("acme") do
  Article.all  # WHERE tenant_id = 'acme'
  Article.create!(title: "Hello")  # tenant_id = 'acme'
end

# Permanent switch
BetterTenant::Tenant.switch!("acme")
Article.all  # WHERE tenant_id = 'acme'

# Reset to no tenant
BetterTenant::Tenant.reset
```

### Automatic Scoping

```ruby
BetterTenant::Tenant.switch("acme") do
  # All queries are scoped
  Article.all
  # SQL: SELECT * FROM articles WHERE tenant_id = 'acme'

  Article.where(published: true)
  # SQL: SELECT * FROM articles WHERE tenant_id = 'acme' AND published = true

  Article.find(1)
  # SQL: SELECT * FROM articles WHERE tenant_id = 'acme' AND id = 1

  # Associations are scoped too
  article = Article.first
  article.comments
  # SQL: SELECT * FROM comments WHERE tenant_id = 'acme' AND article_id = ?
end
```

### Automatic tenant_id Assignment

```ruby
BetterTenant::Tenant.switch("acme") do
  article = Article.new(title: "Test")
  article.tenant_id  # => nil

  article.save!
  article.tenant_id  # => "acme"
end
```

### Cross-Tenant Queries

```ruby
# Unscoped access
Article.unscoped_tenant do
  Article.all  # Returns ALL articles from all tenants
  Article.count  # Total count across tenants
end

# Check specific tenant data
Article.unscoped_tenant do
  Article.where(tenant_id: "globex").count
end
```

## Advanced Configuration

### Custom Tenant Column

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :organization_id  # Custom column name
end
```

### Dynamic Tenant Names

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id

  # Dynamic loading from database
  config.tenant_names -> { Organization.pluck(:slug) }
end
```

### Using tenant_model

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :organization_id
  config.tenant_model "Organization"
  config.tenant_identifier :slug
end
```

### Strict Mode

Prevent changing tenant_id after creation:

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.strict_mode true
end

# In application:
BetterTenant::Tenant.switch("acme") do
  article = Article.create!(title: "Test")
  article.tenant_id = "globex"
  article.save!  # Raises TenantImmutableError
end
```

### Require Tenant Context

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.require_tenant true  # Default
end

# Without tenant context:
Article.all  # Raises TenantContextMissingError
```

## Excluded Models

Some models should not be tenant-scoped:

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.excluded_models %w[User Organization Admin::Setting]
end

# Excluded models don't need the extension
class User < ApplicationRecord
  # No include BetterTenant::ActiveRecordExtension
  # Works normally without tenant filtering
end
```

## Testing

### RSpec Setup

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    BetterTenant.reset!
    BetterTenant.configure do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[test_tenant other_tenant]
    end
  end

  config.around(:each, :tenant) do |example|
    BetterTenant::Tenant.switch("test_tenant") do
      example.run
    end
  end
end
```

### Testing Tenant Isolation

```ruby
describe Article, :tenant do
  it "creates article with tenant_id" do
    article = Article.create!(title: "Test")
    expect(article.tenant_id).to eq("test_tenant")
  end

  it "only returns tenant's articles" do
    Article.create!(title: "My Article")

    BetterTenant::Tenant.switch("other_tenant") do
      Article.create!(title: "Other Article")
    end

    expect(Article.count).to eq(1)
    expect(Article.first.title).to eq("My Article")
  end
end
```

## Performance Considerations

### Indexes

Always add indexes on the tenant column:

```ruby
add_index :articles, :tenant_id
add_index :articles, [:tenant_id, :created_at]  # Composite for common queries
add_index :articles, [:tenant_id, :status]
```

### Query Optimization

The default scope adds `WHERE tenant_id = ?` to all queries. Consider:

1. Composite indexes for frequently filtered columns
2. Partitioning by tenant_id for large tables
3. Connection pooling per tenant (if needed)

## Common Issues

### Missing tenant_id

```ruby
# Error: column "tenant_id" does not exist
# Solution: Run migration to add column

rails generate migration AddTenantIdToArticles tenant_id:string
rails db:migrate
```

### Tenant Not Found

```ruby
# Error: TenantNotFoundError
# Solution: Add tenant to tenant_names list

BetterTenant.configure do |config|
  config.tenant_names %w[acme globex initech new_tenant]
end
```

### Cross-Tenant Data Leak

```ruby
# Problem: Seeing other tenant's data
# Check:
# 1. Model includes ActiveRecordExtension
# 2. Tenant is switched before query
# 3. Model is not in excluded_models
```
