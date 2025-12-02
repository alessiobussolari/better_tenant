# Rake Tasks - Quick Reference

Command-line tasks for tenant management.

---

## Available Tasks

| Task | Description | Strategy |
|------|-------------|----------|
| `better_tenant:list` | List tenants | Both |
| `better_tenant:config` | Show config | Both |
| `better_tenant:create[tenant]` | Create schema | Schema |
| `better_tenant:drop[tenant]` | Drop schema | Schema |
| `better_tenant:migrate` | Migrate all | Schema |
| `better_tenant:rollback` | Rollback all | Schema |
| `better_tenant:seed` | Seed all | Both |
| `better_tenant:console[tenant]` | Console | Both |
| `better_tenant:each[task]` | Run task for all | Both |

---

## Usage Examples

```bash
# List tenants with status
rake better_tenant:list
# Configured tenants:
#   ✓ acme
#   ✓ globex

# Show configuration
rake better_tenant:config

# Create tenant schema
rake better_tenant:create[acme]

# Drop tenant (with confirmation)
rake better_tenant:drop[acme]

# Migrate all tenants
rake better_tenant:migrate

# Rollback all tenants
rake better_tenant:rollback

# Seed all tenants
rake better_tenant:seed

# Console in tenant context
rake better_tenant:console[acme]

# Run custom task for all tenants
rake better_tenant:each[db:seed]
```

---

## Custom Tasks

```ruby
# lib/tasks/tenant.rake
namespace :tenant do
  task cleanup: :environment do
    BetterTenant::Tenant.each do |tenant|
      puts "Cleaning #{tenant}..."
      Article.where("created_at < ?", 1.year.ago).delete_all
    end
  end
end
```

---

## Error Handling

```bash
# Missing configuration
Error: BetterTenant is not configured

# Wrong strategy
Error: This task is only available for schema strategy

# Missing argument
Usage: rake better_tenant:create[tenant_name]
```
