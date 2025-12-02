# Rake Tasks

Command-line tasks for managing tenants in BetterTenant.

---

## Overview

BetterTenant provides rake tasks for common tenant management operations. These tasks are automatically loaded when the gem is installed.

## Available Tasks

| Task | Description | Strategy |
|------|-------------|----------|
| `better_tenant:list` | List all configured tenants | Both |
| `better_tenant:config` | Show current configuration | Both |
| `better_tenant:create[tenant]` | Create a tenant schema | Schema only |
| `better_tenant:drop[tenant]` | Drop a tenant schema | Schema only |
| `better_tenant:migrate` | Run migrations for all tenants | Schema only |
| `better_tenant:rollback` | Rollback migrations for all tenants | Schema only |
| `better_tenant:seed` | Seed all tenants | Both |
| `better_tenant:console[tenant]` | Open console in tenant context | Both |
| `better_tenant:each[task]` | Run a task for each tenant | Both |

---

## Task Details

### better_tenant:list

Lists all configured tenants with their existence status.

```bash
rake better_tenant:list
```

**Output:**

```
Configured tenants:
  ✓ acme
  ✓ globex
  ✗ initech
```

- `✓` indicates the tenant exists (schema exists or is in tenant_names)
- `✗` indicates the tenant is configured but doesn't exist yet

---

### better_tenant:config

Displays the current BetterTenant configuration.

```bash
rake better_tenant:config
```

**Output (Column Strategy):**

```
BetterTenant Configuration:
  Strategy: column
  Tenant column: tenant_id
  Require tenant: false
  Strict mode: false
  Excluded models: User, Tenant
```

**Output (Schema Strategy):**

```
BetterTenant Configuration:
  Strategy: schema
  Require tenant: true
  Strict mode: false
  Excluded models: User, Tenant, Plan
  Persistent schemas: shared, public
  Schema format: tenant_%{tenant}
```

---

### better_tenant:create[tenant]

Creates a new tenant schema. **Schema strategy only.**

```bash
rake better_tenant:create[acme]
```

**Output:**

```
Creating tenant: acme
Tenant 'acme' created successfully!
```

**Errors:**

```
Error: Tenant 'acme' is not in the tenant_names list
```

**Notes:**
- The tenant must be in your `tenant_names` configuration
- Runs `before_create` and `after_create` callbacks
- Creates the schema using the configured `schema_format`

---

### better_tenant:drop[tenant]

Drops a tenant schema and all its data. **Schema strategy only.**

```bash
rake better_tenant:drop[acme]
```

**Output:**

```
WARNING: This will permanently delete all data in tenant 'acme'!
Type 'yes' to confirm: yes
Tenant 'acme' dropped successfully!
```

If cancelled:

```
Operation cancelled.
```

**Warning:** This operation is destructive and cannot be undone.

---

### better_tenant:migrate

Runs database migrations for all tenant schemas. **Schema strategy only.**

```bash
rake better_tenant:migrate
```

**Output:**

```
Running migrations for all tenants...
  Migrating tenant: acme
  Migrating tenant: globex
  Migrating tenant: initech
All tenant migrations completed!
```

**Equivalent to:**

```bash
# For each tenant
BetterTenant::Tenant.switch(tenant) do
  rake db:migrate
end
```

---

### better_tenant:rollback

Rolls back the last migration for all tenant schemas. **Schema strategy only.**

```bash
rake better_tenant:rollback
```

**Output:**

```
Rolling back migrations for all tenants...
  Rolling back tenant: acme
  Rolling back tenant: globex
  Rolling back tenant: initech
All tenant rollbacks completed!
```

---

### better_tenant:seed

Runs `db:seed` for all tenants.

```bash
rake better_tenant:seed
```

**Output:**

```
Seeding all tenants...
  Seeding tenant: acme
  Seeding tenant: globex
  Seeding tenant: initech
All tenants seeded!
```

**Note:** Your `db/seeds.rb` should be tenant-aware. The seed file runs within each tenant's context.

**Example seeds.rb:**

```ruby
# db/seeds.rb
tenant = BetterTenant::Tenant.current

# Common seed data for all tenants
Category.find_or_create_by!(name: "General")
Category.find_or_create_by!(name: "News")

# Tenant-specific seed data
if tenant
  Setting.find_or_create_by!(key: "site_name") do |s|
    s.value = tenant.titleize
  end
end
```

---

### better_tenant:console[tenant]

Opens a Rails console with the specified tenant context.

```bash
rake better_tenant:console[acme]
```

**Output:**

```
Switched to tenant: acme
Starting Rails console...
irb(main):001:0>
```

**Usage:**

```ruby
irb(main):001:0> Article.count
=> 42
irb(main):002:0> BetterTenant::Tenant.current
=> "acme"
```

---

### better_tenant:each[task]

Executes any rake task for each configured tenant.

```bash
rake better_tenant:each[db:seed]
```

**Output:**

```
Running 'db:seed' for all tenants...
  Tenant: acme
  Tenant: globex
  Tenant: initech
Task completed for all tenants!
```

**Examples:**

```bash
# Run seeds for all tenants
rake better_tenant:each[db:seed]

# Run custom task for all tenants
rake better_tenant:each[my_namespace:my_task]

# Reset database for all tenants (careful!)
rake better_tenant:each[db:reset]
```

---

## Error Handling

### Configuration Not Found

```
Error: BetterTenant is not configured. Add configuration in config/initializers/better_tenant.rb
```

**Solution:** Ensure you have a proper configuration file:

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names %w[acme globex]
end
```

### Wrong Strategy

```
Error: This task is only available for schema strategy. Current strategy: column
```

**Solution:** Some tasks are schema-strategy only. Use the appropriate strategy or skip these tasks.

### Missing Tenant Name

```
Usage: rake better_tenant:create[tenant_name]
```

**Solution:** Provide the tenant name in brackets:

```bash
rake better_tenant:create[acme]
# or with quotes for shells that require it
rake "better_tenant:create[acme]"
```

---

## Custom Rake Tasks

### Per-Tenant Task

Create custom tasks that run for each tenant:

```ruby
# lib/tasks/tenant_maintenance.rake
namespace :maintenance do
  desc "Clean up old records for all tenants"
  task cleanup: :environment do
    BetterTenant::Tenant.each do |tenant|
      puts "Cleaning up tenant: #{tenant}"

      # Clean up records older than 1 year
      Article.where("created_at < ?", 1.year.ago).delete_all
      Comment.where("created_at < ?", 1.year.ago).delete_all
    end
  end
end
```

Run with:

```bash
rake maintenance:cleanup
```

### Single-Tenant Task

Create a task for a specific tenant:

```ruby
# lib/tasks/tenant_reports.rake
namespace :reports do
  desc "Generate report for a specific tenant"
  task :generate, [:tenant] => :environment do |t, args|
    tenant = args[:tenant]
    abort "Usage: rake reports:generate[tenant_name]" unless tenant

    BetterTenant::Tenant.switch(tenant) do
      puts "Generating report for #{tenant}..."

      report = {
        total_articles: Article.count,
        total_users: User.count,
        revenue: Order.sum(:total)
      }

      puts report.to_json
    end
  end
end
```

Run with:

```bash
rake reports:generate[acme]
```

### Parallel Tenant Processing

For large numbers of tenants, process in parallel:

```ruby
# lib/tasks/tenant_parallel.rake
namespace :parallel do
  desc "Process all tenants in parallel"
  task process: :environment do
    require "parallel"

    tenants = BetterTenant::Tenant.tenant_names

    Parallel.each(tenants, in_processes: 4) do |tenant|
      BetterTenant::Tenant.switch(tenant) do
        # Process tenant data
        puts "Processing #{tenant} in process #{Process.pid}"
      end
    end
  end
end
```

---

## Best Practices

1. **Always test tasks in development first** before running in production
2. **Back up data** before running destructive tasks like `drop` or `rollback`
3. **Use transactions** in custom tasks when appropriate
4. **Log task execution** for audit purposes
5. **Handle errors gracefully** in custom tasks to prevent cascading failures

```ruby
namespace :tenant do
  task safe_cleanup: :environment do
    BetterTenant::Tenant.each do |tenant|
      begin
        puts "Processing: #{tenant}"
        # Your cleanup logic
      rescue => e
        puts "Error in #{tenant}: #{e.message}"
        # Continue with next tenant
      end
    end
  end
end
```
