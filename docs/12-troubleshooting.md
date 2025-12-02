# Troubleshooting & FAQ

Common issues, solutions, and frequently asked questions for BetterTenant.

---

## Common Issues

### Column Strategy Issues

#### Records not being filtered by tenant

**Symptom:** Queries return records from all tenants instead of just the current tenant.

**Causes and Solutions:**

1. **Model doesn't include extension:**
   ```ruby
   class Article < ApplicationRecord
     include BetterTenant::ActiveRecordExtension  # Add this
   end
   ```

2. **No tenant context set:**
   ```ruby
   # Check if tenant is set
   BetterTenant::Tenant.current  # => nil means no tenant

   # Set tenant before queries
   BetterTenant::Tenant.switch!("acme")
   ```

3. **require_tenant is false:**
   ```ruby
   BetterTenant.configure do |config|
     config.require_tenant true  # Enforce tenant context
   end
   ```

#### tenant_id not being set on new records

**Symptom:** New records have `nil` tenant_id.

**Solutions:**

1. **Ensure tenant context is set:**
   ```ruby
   BetterTenant::Tenant.switch("acme") do
     Article.create!(title: "Test")  # tenant_id will be "acme"
   end
   ```

2. **Check column name matches configuration:**
   ```ruby
   # config/initializers/better_tenant.rb
   config.tenant_column :tenant_id  # Must match your database column
   ```

#### TenantImmutableError when updating records

**Symptom:** Can't update records, getting `TenantImmutableError`.

**Cause:** `strict_mode` is enabled and you're trying to change `tenant_id`.

**Solutions:**

1. **Don't change tenant_id:**
   ```ruby
   # Wrong
   article.update!(tenant_id: "new_tenant")

   # Right - update other attributes only
   article.update!(title: "New Title")
   ```

2. **Disable strict mode if needed:**
   ```ruby
   config.strict_mode false
   ```

---

### Schema Strategy Issues

#### SchemaNotFoundError when switching tenants

**Symptom:** `SchemaNotFoundError: Schema 'tenant_acme' not found`

**Solutions:**

1. **Create the schema first:**
   ```bash
   rake better_tenant:create[acme]
   ```

2. **Ensure tenant is in tenant_names:**
   ```ruby
   config.tenant_names %w[acme globex]  # acme must be here
   ```

3. **Check schema format:**
   ```ruby
   # If schema_format is "tenant_%{tenant}"
   # Then "acme" becomes "tenant_acme"
   config.schema_format "tenant_%{tenant}"
   ```

#### Tables not found after switching tenant

**Symptom:** `PG::UndefinedTable: relation "articles" does not exist`

**Causes and Solutions:**

1. **Tables not created in tenant schema:**
   ```bash
   # Run migrations for all tenants
   rake better_tenant:migrate
   ```

2. **Wrong search_path:**
   ```ruby
   # Check current search_path
   BetterTenant::Tenant.switch("acme") do
     result = ActiveRecord::Base.connection.execute("SHOW search_path")
     puts result.first["search_path"]
   end
   ```

#### Migrations not running in tenant schemas

**Symptom:** Migrations only run in public schema.

**Solution:** Use `better_tenant:migrate` instead of `db:migrate`:

```bash
# Wrong - only migrates public schema
rake db:migrate

# Right - migrates all tenant schemas
rake better_tenant:migrate
```

---

### Middleware Issues

#### Tenant not detected from request

**Symptom:** Middleware doesn't set tenant from subdomain/header/path.

**Solutions:**

1. **Ensure middleware is enabled:**
   ```ruby
   # config/application.rb
   config.middleware.use BetterTenant::Middleware, :subdomain
   ```

2. **Check elevator configuration:**
   ```ruby
   config.elevator :subdomain  # Must match middleware setting
   ```

3. **Verify excluded subdomains:**
   ```ruby
   config.excluded_subdomains %w[www admin]  # These won't set tenant
   ```

4. **Debug with custom elevator:**
   ```ruby
   config.middleware.use BetterTenant::Middleware, ->(request) {
     tenant = request.subdomain
     Rails.logger.debug "Detected tenant: #{tenant}"
     tenant
   }
   ```

#### TenantNotFoundError in requests

**Symptom:** Requests fail with `TenantNotFoundError`.

**Solutions:**

1. **Add tenant to tenant_names:**
   ```ruby
   config.tenant_names %w[acme globex]  # Add missing tenant
   ```

2. **Handle unknown tenants gracefully:**
   ```ruby
   # app/controllers/application_controller.rb
   rescue_from BetterTenant::Errors::TenantNotFoundError do |e|
     redirect_to root_url, alert: "Unknown organization"
   end
   ```

3. **Use dynamic tenant_names:**
   ```ruby
   config.tenant_names -> { Organization.pluck(:subdomain) }
   ```

---

### ActiveJob Issues

#### Job executes in wrong tenant

**Symptom:** Background job processes data for wrong tenant.

**Solutions:**

1. **Include extension in job:**
   ```ruby
   class ProcessOrderJob < ApplicationJob
     include BetterTenant::ActiveJobExtension  # Add this
   end
   ```

2. **Verify tenant is captured:**
   ```ruby
   with_tenant("acme") do
     job = ProcessOrderJob.new(order.id)
     puts job.tenant_for_job  # Should be "acme"
   end
   ```

#### Tenant not available in job

**Symptom:** `BetterTenant::Tenant.current` returns `nil` in job.

**Cause:** Job was enqueued without tenant context.

**Solution:** Ensure tenant is set when enqueuing:

```ruby
BetterTenant::Tenant.switch("acme") do
  ProcessOrderJob.perform_later(order.id)
end
```

---

### Configuration Issues

#### ConfigurationError on startup

**Symptom:** App won't start, raises `ConfigurationError`.

**Common causes:**

1. **Invalid strategy:**
   ```ruby
   config.strategy :column  # Valid: :column or :schema
   ```

2. **Invalid elevator:**
   ```ruby
   config.elevator :subdomain  # Valid: :subdomain, :domain, :header, :path, or Proc
   ```

3. **Empty tenant_names with require_tenant:**
   ```ruby
   config.tenant_names %w[acme]  # Add at least one tenant
   config.require_tenant true
   ```

---

## Debug Workflow

### 1. Check Configuration

```ruby
# Rails console
BetterTenant::Tenant.configuration
# => {:strategy=>:column, :tenant_column=>:tenant_id, ...}
```

### 2. Check Current Tenant

```ruby
BetterTenant::Tenant.current
# => "acme" or nil
```

### 3. Check Search Path (Schema Strategy)

```ruby
BetterTenant::Tenant.switch("acme") do
  ActiveRecord::Base.connection.execute("SHOW search_path").first
end
# => {"search_path"=>"tenant_acme, public"}
```

### 4. Enable Audit Logging

```ruby
BetterTenant.configure do |config|
  config.audit_access true
  config.audit_violations true
end
```

Then check logs:

```
[BetterTenant] Tenant switch: from=nil to=acme timestamp=2024-01-15T10:30:00Z
[BetterTenant] Tenant access: tenant=acme model=Article operation=query
```

### 5. Test in Console

```ruby
# Test tenant switching
BetterTenant::Tenant.switch("acme") do
  puts "Tenant: #{BetterTenant::Tenant.current}"
  puts "Articles: #{Article.count}"
end

# Test unscoped queries
Article.unscoped_tenant { Article.count }
```

---

## Frequently Asked Questions

### General

**Q: Can I use BetterTenant with MySQL?**

A: Column strategy works with any database (MySQL, SQLite, PostgreSQL). Schema strategy is PostgreSQL only.

**Q: Can I switch strategies after deployment?**

A: It's possible but requires data migration. Column to schema requires creating schemas and moving data. Schema to column requires adding tenant_id column and consolidating data.

**Q: Does BetterTenant work with Rails < 8.1?**

A: No, BetterTenant requires Rails 8.1+ and Ruby 3.2+.

---

### Column Strategy

**Q: Do I need to add tenant_id to every table?**

A: Only tables that should be tenant-scoped need the column. Shared tables (like User, Plan) should be in `excluded_models`.

**Q: Can I use a different column name?**

A: Yes:
```ruby
config.tenant_column :organization_id
```

**Q: Can tenant_id be an integer instead of string?**

A: Yes, the column type is flexible. Just ensure your tenant_names match:
```ruby
config.tenant_names [1, 2, 3]
# or
config.tenant_names -> { Organization.pluck(:id) }
```

---

### Schema Strategy

**Q: How do I run migrations for a single tenant?**

A:
```ruby
BetterTenant::Tenant.switch("acme") do
  ActiveRecord::MigrationContext.new(
    Rails.root.join("db/migrate")
  ).migrate
end
```

**Q: How do I backup a single tenant?**

A:
```bash
pg_dump -n tenant_acme mydb > acme_backup.sql
```

**Q: Can I have different schemas for different tables?**

A: No, all tenant tables use the same schema. Use `excluded_models` for shared tables.

---

### Centralized Login

**Q: How do I handle login from the main domain without subdomain?**

A: Use session-based tenant detection. See the [Centralized Login Guide](14-centralized-login.md) for complete implementation:

```ruby
# 1. Allow requests without tenant
config.require_tenant false

# 2. Use session-based middleware
config.middleware.use BetterTenant::Middleware, ->(request) {
  request.session[:current_tenant_id] || extract_subdomain(request.host)
}

# 3. Set session after login
session[:current_tenant_id] = current_user.default_tenant
```

**Q: How do I allow a user to access multiple tenants?**

A: Create a `memberships` table to map users to tenants:

```ruby
# Migration
create_table :memberships do |t|
  t.references :user, null: false
  t.string :tenant_id, null: false
  t.string :role, default: "member"
end

# After login, if user has multiple tenants
if current_user.memberships.count > 1
  redirect_to select_tenant_path
else
  session[:current_tenant_id] = current_user.default_tenant
end
```

See [Centralized Login](14-centralized-login.md) for the complete pattern.

---

### Middleware

**Q: Can I use multiple elevators?**

A: Use a custom Proc:
```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  request.headers["X-Tenant"] || request.subdomain
}
```

**Q: How do I skip tenant detection for certain paths?**

A:
```ruby
config.excluded_paths %w[api admin health]
```

**Q: Can I detect tenant from JWT token?**

A:
```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  token = request.headers["Authorization"]&.split(" ")&.last
  JWT.decode(token, secret).first["tenant_id"] rescue nil
}
```

---

### ActiveJob

**Q: Does tenant context work with Sidekiq?**

A: Yes, BetterTenant serializes tenant in job arguments. Works with any ActiveJob adapter.

**Q: How do I run a job for all tenants?**

A:
```ruby
BetterTenant::Tenant.tenant_names.each do |tenant|
  BetterTenant::Tenant.switch(tenant) do
    ProcessJob.perform_later
  end
end
```

**Q: How do I handle failed jobs with missing tenant?**

A:
```ruby
class ProcessJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  rescue_from BetterTenant::Errors::TenantNotFoundError do |e|
    Rails.logger.error "Tenant not found: #{e.tenant_name}"
    # Don't retry
  end
end
```

---

### Testing

**Q: How do I test without tenant context?**

A:
```ruby
BetterTenant.configure do |config|
  config.require_tenant false  # For tests
end
```

**Q: How do I reset BetterTenant between tests?**

A:
```ruby
after(:each) do
  BetterTenant.reset!
  BetterTenant::Tenant.reset rescue nil
end
```

---

### Performance

**Q: Does tenant scoping add overhead?**

A: Column strategy adds a WHERE clause. Schema strategy adds search_path switch. Both are minimal overhead with proper indexes.

**Q: How do I optimize multi-tenant queries?**

A:
1. Add index on tenant_id column
2. Use composite indexes: `add_index :articles, [:tenant_id, :created_at]`
3. Partition large tables by tenant_id

**Q: Should I use connection pooling with schema strategy?**

A: Yes, each tenant switch modifies the connection. Use PgBouncer in transaction mode for best results.

---

## Error Reference

| Error | Cause | Solution |
|-------|-------|----------|
| `TenantNotFoundError` | Tenant not in tenant_names | Add tenant to config or use dynamic list |
| `TenantContextMissingError` | No tenant set with require_tenant=true | Set tenant before operation |
| `TenantImmutableError` | Changing tenant_id with strict_mode=true | Don't change tenant_id or disable strict mode |
| `TenantMismatchError` | Record tenant doesn't match current | Verify you're in correct tenant context |
| `SchemaNotFoundError` | PostgreSQL schema doesn't exist | Create schema with `Tenant.create()` |
| `ConfigurationError` | Invalid configuration | Check strategy, elevator, tenant_names |
