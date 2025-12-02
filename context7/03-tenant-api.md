# Tenant API

Core tenant operations.

---

## Get Current Tenant

```ruby
BetterTenant::Tenant.current
# => "acme" or nil
```

--------------------------------

## Switch Tenant (Block)

```ruby
BetterTenant::Tenant.switch("acme") do
  Article.all  # Scoped
end
```

--------------------------------

## Switch Tenant (Permanent)

```ruby
BetterTenant::Tenant.switch!("acme")
Article.all  # Scoped until reset
```

--------------------------------

## Reset Tenant

```ruby
BetterTenant::Tenant.reset
```

--------------------------------

## Check Existence

```ruby
BetterTenant::Tenant.exists?("acme")
# => true/false
```

--------------------------------

## List All Tenants

```ruby
BetterTenant::Tenant.tenant_names
# => ["acme", "globex"]
```

--------------------------------

## Iterate Tenants

```ruby
BetterTenant::Tenant.each do |tenant|
  puts "#{tenant}: #{Article.count}"
end
```

--------------------------------

## Create Tenant (Schema)

```ruby
BetterTenant::Tenant.create("new_tenant")
# Creates PostgreSQL schema
```

--------------------------------

## Drop Tenant (Schema)

```ruby
BetterTenant::Tenant.drop("old_tenant")
# Drops schema CASCADE
```

--------------------------------

## Unscoped Access (Column)

```ruby
Article.unscoped_tenant do
  Article.count  # All tenants
end
```

--------------------------------
