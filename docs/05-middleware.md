# Middleware & Elevators

Automatic tenant detection from HTTP requests.

---

## Overview

BetterTenant provides Rack middleware that automatically detects and switches tenants based on incoming requests. The middleware uses "elevators" to extract tenant information from different parts of the request.

## Setup

```ruby
# config/application.rb
class Application < Rails::Application
  config.middleware.use BetterTenant::Middleware, :subdomain
end
```

## Available Elevators

### Subdomain Elevator

Extracts tenant from subdomain:

```ruby
config.middleware.use BetterTenant::Middleware, :subdomain

# acme.example.com -> tenant "acme"
# globex.example.com -> tenant "globex"
# www.example.com -> ignored (excluded subdomain)
```

Configuration:

```ruby
BetterTenant.configure do |config|
  config.elevator :subdomain
  config.excluded_subdomains %w[www admin api staging]
end
```

### Domain Elevator

Uses full domain as tenant:

```ruby
config.middleware.use BetterTenant::Middleware, :domain

# acme.com -> tenant "acme.com"
# globex.io -> tenant "globex.io"
```

### Header Elevator

Extracts tenant from HTTP header:

```ruby
config.middleware.use BetterTenant::Middleware, :header

# Request with "X-Tenant: acme" header -> tenant "acme"
```

Default header: `X-Tenant` (via `HTTP_X_TENANT` env key)

### Path Elevator

Extracts tenant from first path segment:

```ruby
config.middleware.use BetterTenant::Middleware, :path

# /acme/articles -> tenant "acme"
# /globex/products/1 -> tenant "globex"
# /api/v1/users -> ignored (excluded path)
```

Configuration:

```ruby
BetterTenant.configure do |config|
  config.elevator :path
  config.excluded_paths %w[api admin assets images rails]
end
```

### Custom Elevator (Proc)

Define custom tenant extraction logic:

```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  # Extract from query parameter
  request.params["tenant"]
}

# Or more complex logic
config.middleware.use BetterTenant::Middleware, ->(request) {
  # Try multiple sources
  request.env["HTTP_X_TENANT"] ||
    request.params["tenant"] ||
    request.session[:tenant] ||
    extract_from_host(request.host)
}
```

## Middleware Behavior

### Request Flow

```
1. Request arrives
2. Middleware extracts tenant using elevator
3. If tenant found and exists:
   - Switch to tenant context
   - Process request
   - Reset tenant after response
4. If tenant not found:
   - If require_tenant: true -> Raise error
   - If require_tenant: false -> Process without tenant
5. If tenant doesn't exist:
   - Raise TenantNotFoundError (if required)
```

### Error Handling

```ruby
BetterTenant.configure do |config|
  config.require_tenant true  # Strict mode
end

# Missing tenant -> TenantContextMissingError
# Invalid tenant -> TenantNotFoundError
```

Handle errors in your application:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  rescue_from BetterTenant::Errors::TenantNotFoundError do |e|
    render status: :not_found, json: { error: "Tenant not found" }
  end

  rescue_from BetterTenant::Errors::TenantContextMissingError do |e|
    render status: :bad_request, json: { error: "Tenant required" }
  end
end
```

## Configuration Options

### Excluded Subdomains

Default excluded: `["www"]`

```ruby
BetterTenant.configure do |config|
  config.excluded_subdomains %w[www admin api staging beta]
end

# www.example.com -> no tenant (excluded)
# admin.example.com -> no tenant (excluded)
# acme.example.com -> tenant "acme"
```

### Excluded Paths

Default excluded: `["api", "admin", "assets", "images", "stylesheets", "javascripts", "rails"]`

```ruby
BetterTenant.configure do |config|
  config.excluded_paths %w[api admin assets webhooks health]
end

# /api/v1/users -> no tenant (excluded)
# /admin/dashboard -> no tenant (excluded)
# /acme/articles -> tenant "acme"
```

### Require Tenant

```ruby
BetterTenant.configure do |config|
  # Strict: require tenant for all requests
  config.require_tenant true

  # Lenient: allow requests without tenant
  config.require_tenant false
end
```

## Advanced Patterns

### Multiple Elevators

Use Proc for fallback logic:

```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  # Try subdomain first
  host = request.host
  parts = host.split(".")
  if parts.length >= 3
    subdomain = parts.first
    return subdomain unless %w[www admin].include?(subdomain)
  end

  # Fall back to header
  request.env["HTTP_X_TENANT"]
}
```

### API vs Web Detection

```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  if request.path.start_with?("/api")
    # API: use header
    request.env["HTTP_X_TENANT"]
  else
    # Web: use subdomain
    extract_subdomain(request.host)
  end
}
```

### Session-Based Tenant

```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  # For logged-in users, use their organization
  if request.session[:current_organization]
    request.session[:current_organization]
  else
    # For visitors, use subdomain
    extract_subdomain(request.host)
  end
}
```

### JWT Token Tenant

```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  auth_header = request.env["HTTP_AUTHORIZATION"]
  return nil unless auth_header&.start_with?("Bearer ")

  token = auth_header.sub("Bearer ", "")
  payload = JWT.decode(token, secret_key).first
  payload["tenant"]
rescue JWT::DecodeError
  nil
}
```

## Middleware Placement

### Position in Stack

```ruby
# After session middleware (for session-based tenant)
config.middleware.insert_after ActionDispatch::Session::CookieStore,
  BetterTenant::Middleware, :subdomain

# Before routing (default position)
config.middleware.use BetterTenant::Middleware, :subdomain

# Check middleware stack
rake middleware
```

### Per-Environment

```ruby
# config/environments/production.rb
config.middleware.use BetterTenant::Middleware, :subdomain

# config/environments/development.rb
config.middleware.use BetterTenant::Middleware, :header

# config/environments/test.rb
# Don't use middleware in tests (switch manually)
```

## Testing

### Integration Tests

```ruby
# spec/requests/articles_spec.rb
describe "Articles API" do
  before do
    BetterTenant.configure do |c|
      c.strategy :column
      c.tenant_names %w[acme]
    end
  end

  it "scopes to tenant from header" do
    get "/articles", headers: { "X-Tenant" => "acme" }
    expect(response).to be_successful
  end

  it "rejects invalid tenant" do
    get "/articles", headers: { "X-Tenant" => "invalid" }
    expect(response).to have_http_status(:not_found)
  end
end
```

### Request Specs with Subdomain

```ruby
# spec/requests/subdomain_spec.rb
describe "Subdomain tenant" do
  it "extracts tenant from subdomain" do
    host! "acme.example.com"
    get "/articles"
    expect(response).to be_successful
  end
end
```

## Debugging

### Check Tenant in Request

```ruby
# In controller
def show
  Rails.logger.info "Current tenant: #{BetterTenant::Tenant.current}"
end
```

### Middleware Logging

```ruby
BetterTenant.configure do |config|
  config.before_switch do |from, to|
    Rails.logger.info "[Middleware] Tenant: #{from} -> #{to}"
  end
end
```

### Inspect Request

```ruby
config.middleware.use BetterTenant::Middleware, ->(request) {
  Rails.logger.debug "Host: #{request.host}"
  Rails.logger.debug "Path: #{request.path}"
  Rails.logger.debug "Headers: #{request.env.select { |k, _| k.start_with?('HTTP_') }}"

  # Your extraction logic
  request.env["HTTP_X_TENANT"]
}
```
