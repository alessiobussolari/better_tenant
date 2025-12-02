# Centralized Login - Quick Reference

Session-based tenant detection for neutral domain access.

---

## Problem

Users access `myservice.com` (no subdomain/path) and need tenant context after login.

## Solution

Store tenant in session after authentication.

---

## Database Setup

```ruby
# Migration for multi-tenant users
create_table :memberships do |t|
  t.references :user, null: false, foreign_key: true
  t.string :tenant_id, null: false
  t.string :role, default: "member"
  t.timestamps
end

# Model
class User < ApplicationRecord
  has_many :memberships

  def tenants
    memberships.pluck(:tenant_id)
  end

  def has_access_to?(tenant_id)
    memberships.exists?(tenant_id: tenant_id)
  end

  def default_tenant
    memberships.first&.tenant_id
  end
end
```

---

## Configuration

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.require_tenant false  # Allow login page
  config.excluded_models %w[User Membership]

  # Validate access
  config.before_switch do |from, to|
    next unless to && defined?(Current) && Current.user
    raise "Access denied" unless Current.user.has_access_to?(to)
  end
end
```

---

## Middleware

```ruby
# config/application.rb
config.middleware.use BetterTenant::Middleware, ->(request) {
  # Session first, subdomain fallback
  if request.session[:current_tenant_id].present?
    request.session[:current_tenant_id]
  else
    subdomain = request.host.split(".").first
    subdomain unless %w[www app].include?(subdomain)
  end
}
```

---

## Sessions Controller

```ruby
class SessionsController < ApplicationController
  skip_before_action :require_tenant!

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      session[:user_id] = user.id

      if user.tenants.count == 1
        session[:current_tenant_id] = user.default_tenant
        redirect_to root_path
      else
        redirect_to select_tenant_path
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:user_id)
    session.delete(:current_tenant_id)
    redirect_to login_path
  end
end
```

---

## Tenant Switching

```ruby
class TenantsController < ApplicationController
  skip_before_action :require_tenant!, only: [:select, :switch]

  def select
    @tenants = Current.user.memberships
  end

  def switch
    tenant_id = params[:tenant_id]

    if Current.user.has_access_to?(tenant_id)
      session[:current_tenant_id] = tenant_id
      redirect_to root_path
    else
      redirect_to select_tenant_path, alert: "Access denied"
    end
  end
end
```

---

## Routes

```ruby
get "login", to: "sessions#new"
post "login", to: "sessions#create"
delete "logout", to: "sessions#destroy"
get "select_tenant", to: "tenants#select"
post "switch_tenant", to: "tenants#switch"
```

---

## Security Checklist

- [ ] `require_tenant false` in config
- [ ] Validate access in `before_switch` callback
- [ ] `reset_session` on login (prevent fixation)
- [ ] Generic error messages (prevent enumeration)
- [ ] Exclude User/Membership from tenancy
