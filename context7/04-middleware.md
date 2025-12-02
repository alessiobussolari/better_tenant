# Middleware

Automatic tenant detection from requests.

---

## Setup

```ruby
# config/application.rb
config.middleware.use BetterTenant::Middleware, :subdomain
```

--------------------------------

## Subdomain Elevator

```ruby
config.middleware.use BetterTenant::Middleware, :subdomain
# acme.example.com -> "acme"
```

--------------------------------

## Header Elevator

```ruby
config.middleware.use BetterTenant::Middleware, :header
# X-Tenant: acme -> "acme"
```

--------------------------------

## Path Elevator

```ruby
config.middleware.use BetterTenant::Middleware, :path
# /acme/articles -> "acme"
```

--------------------------------

## Domain Elevator

```ruby
config.middleware.use BetterTenant::Middleware, :domain
# acme.com -> "acme.com"
```

--------------------------------

## Custom Elevator

```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  request.params["tenant"] ||
  request.env["HTTP_X_TENANT"] ||
  extract_from_host(request.host)
}
```

--------------------------------

## Excluded Subdomains

```ruby
config.excluded_subdomains %w[www admin api]
```

Default: `["www"]`

--------------------------------

## Excluded Paths

```ruby
config.excluded_paths %w[api admin assets]
```

Default: `["api", "admin", "assets", "rails"]`

--------------------------------

## Error Handling

```ruby
rescue_from BetterTenant::Errors::TenantNotFoundError do |e|
  render status: :not_found
end

rescue_from BetterTenant::Errors::TenantContextMissingError do |e|
  render status: :bad_request
end
```

--------------------------------
