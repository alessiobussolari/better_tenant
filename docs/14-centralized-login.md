# Centralized Login

Session-based tenant detection for applications with a neutral domain.

---

## Overview

### The Problem

When users access your application from a neutral domain (e.g., `myservice.com` without subdomain or path), the middleware cannot determine the tenant from the URL. This is common in:

- **Login pages** - Users authenticate before tenant context is known
- **Email links** - Links pointing to the main domain
- **Single sign-on** - Authentication happens before tenant selection
- **Multi-tenant users** - Users with access to multiple organizations

### The Solution

Use **session-based tenant detection**: after login, store the user's tenant in the session and use it for all subsequent requests.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   User      │────▶│   Login     │────▶│   Tenant    │────▶│   Session   │
│   Request   │     │   Page      │     │   Discovery │     │   Storage   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                                                   │
                    ┌─────────────┐     ┌─────────────┐            │
                    │   Tenant    │◀────│  Middleware │◀───────────┘
                    │   Context   │     │   (Proc)    │
                    └─────────────┘     └─────────────┘
```

---

## Architecture

### Components

1. **User Model** - Your user authentication model
2. **Membership Model** - Maps users to tenants (for multi-tenant users)
3. **Session** - Stores current tenant after login
4. **Middleware (Proc)** - Reads tenant from session

### Single-Tenant vs Multi-Tenant Users

| Scenario | Database Design | After Login |
|----------|-----------------|-------------|
| User belongs to ONE tenant | `users.tenant_id` column | Auto-select tenant |
| User can access MULTIPLE tenants | `memberships` join table | Show tenant selector |

---

## Database Setup

### Option A: Single-Tenant Users

Each user belongs to exactly one tenant:

```ruby
# Migration
class AddTenantIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tenant_id, :string, null: false
    add_index :users, :tenant_id
  end
end

# Model
class User < ApplicationRecord
  # User is excluded from tenancy (shared table)
  validates :tenant_id, presence: true

  def tenant
    tenant_id
  end
end
```

### Option B: Multi-Tenant Users (Recommended)

Users can access multiple tenants with different roles:

```ruby
# Migration
class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.string :tenant_id, null: false
      t.string :role, default: "member"  # owner, admin, member
      t.timestamps
    end

    add_index :memberships, [:user_id, :tenant_id], unique: true
    add_index :memberships, :tenant_id
  end
end

# Models
class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :tenant_ids, through: :memberships

  def tenants
    memberships.pluck(:tenant_id)
  end

  def has_access_to?(tenant_id)
    memberships.exists?(tenant_id: tenant_id)
  end

  def default_tenant
    memberships.order(:created_at).first&.tenant_id
  end

  def role_for(tenant_id)
    memberships.find_by(tenant_id: tenant_id)&.role
  end
end

class Membership < ApplicationRecord
  belongs_to :user

  validates :tenant_id, presence: true
  validates :role, inclusion: { in: %w[owner admin member] }
  validates :user_id, uniqueness: { scope: :tenant_id }
end
```

---

## BetterTenant Configuration

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names -> { Organization.pluck(:slug) }

  # IMPORTANT: Allow requests without tenant (for login page)
  config.require_tenant false

  # Exclude User and Membership from tenancy
  config.excluded_models %w[User Membership Organization]

  # Validate tenant access on switch
  config.before_switch do |from_tenant, to_tenant|
    next unless to_tenant

    # Skip validation if no user context (background jobs, etc.)
    next unless defined?(Current) && Current.user

    unless Current.user.has_access_to?(to_tenant)
      raise BetterTenant::Errors::TenantNotFoundError.new(
        tenant_name: to_tenant,
        message: "User does not have access to this tenant"
      )
    end
  end

  # Optional: Log tenant switches
  config.after_switch do |from_tenant, to_tenant|
    if defined?(Current) && Current.user
      Rails.logger.info "[Tenant] #{Current.user.email}: #{from_tenant} -> #{to_tenant}"
    end
  end
end
```

---

## Middleware Configuration

Configure the middleware to read tenant from session with fallback:

```ruby
# config/application.rb
module MyApp
  class Application < Rails::Application
    # Session-based tenant detection with subdomain fallback
    config.middleware.use BetterTenant::Middleware, ->(request) {
      # 1. Try session first (for authenticated users)
      if request.session[:current_tenant_id].present?
        request.session[:current_tenant_id]

      # 2. Fall back to subdomain (for direct tenant URLs)
      elsif (subdomain = extract_subdomain(request.host))
        subdomain

      # 3. No tenant - allow access to login page
      else
        nil
      end
    }

    private

    def self.extract_subdomain(host)
      parts = host.split(".")
      return nil if parts.length < 3

      subdomain = parts.first
      return nil if %w[www app].include?(subdomain)

      subdomain
    end
  end
end
```

### Excluded Paths

Configure paths that should work without tenant:

```ruby
BetterTenant.configure do |config|
  config.excluded_paths %w[
    login
    logout
    signup
    password
    sessions
    registrations
    confirmations
    assets
    health
  ]
end
```

---

## Controller Implementation

### Application Controller

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :set_current_user
  before_action :require_tenant!, except: [:not_found]

  private

  def set_current_user
    Current.user = User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def require_tenant!
    return if tenant_optional_path?
    return if BetterTenant::Tenant.current.present?

    if Current.user
      # User logged in but no tenant - redirect to selector
      redirect_to select_tenant_path
    else
      # Not logged in - redirect to login
      redirect_to login_path
    end
  end

  def tenant_optional_path?
    # Paths that work without tenant
    request.path.match?(%r{^/(login|logout|signup|select_tenant|health)})
  end

  def current_tenant
    BetterTenant::Tenant.current
  end
  helper_method :current_tenant
end
```

### Sessions Controller

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  skip_before_action :require_tenant!

  def new
    # Login page - works without tenant
  end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      Current.user = user

      # Tenant discovery
      if user.tenants.count == 1
        # Single tenant - auto-select
        set_tenant_session(user.default_tenant)
        redirect_to root_path, notice: "Welcome back!"
      elsif user.tenants.count > 1
        # Multiple tenants - show selector
        redirect_to select_tenant_path
      else
        # No tenants - error or create one
        redirect_to new_organization_path, alert: "Please create an organization"
      end
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:user_id)
    session.delete(:current_tenant_id)
    redirect_to login_path, notice: "Logged out successfully"
  end

  private

  def set_tenant_session(tenant_id)
    session[:current_tenant_id] = tenant_id
    # Also switch BetterTenant context for this request
    BetterTenant::Tenant.switch!(tenant_id)
  end
end
```

### Tenant Selector Controller

For users with access to multiple tenants:

```ruby
# app/controllers/tenants_controller.rb
class TenantsController < ApplicationController
  skip_before_action :require_tenant!, only: [:select, :switch]

  # GET /select_tenant
  def select
    @tenants = Current.user.memberships.includes(:organization)
  end

  # POST /switch_tenant
  def switch
    tenant_id = params[:tenant_id]

    unless Current.user.has_access_to?(tenant_id)
      redirect_to select_tenant_path, alert: "Access denied"
      return
    end

    session[:current_tenant_id] = tenant_id
    BetterTenant::Tenant.switch!(tenant_id)

    redirect_to root_path, notice: "Switched to #{tenant_id}"
  end

  # GET /current_tenant (for navbar display)
  def current
    render json: {
      tenant_id: BetterTenant::Tenant.current,
      role: Current.user.role_for(BetterTenant::Tenant.current)
    }
  end
end
```

---

## Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Public routes (no tenant required)
  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  get "select_tenant", to: "tenants#select"
  post "switch_tenant", to: "tenants#switch"

  # Tenant-scoped routes
  resources :articles
  resources :projects

  root "dashboard#index"
end
```

---

## Views

### Tenant Selector

```erb
<%# app/views/tenants/select.html.erb %>
<h1>Select Organization</h1>

<% if @tenants.empty? %>
  <p>You don't have access to any organizations.</p>
  <%= link_to "Create Organization", new_organization_path %>
<% else %>
  <ul>
    <% @tenants.each do |membership| %>
      <li>
        <%= button_to membership.tenant_id, switch_tenant_path(tenant_id: membership.tenant_id), method: :post %>
        <span class="role"><%= membership.role %></span>
      </li>
    <% end %>
  </ul>
<% end %>
```

### Navbar Tenant Switcher

```erb
<%# app/views/shared/_navbar.html.erb %>
<nav>
  <% if current_tenant %>
    <div class="tenant-switcher">
      <span>Current: <%= current_tenant %></span>
      <% if Current.user.tenants.count > 1 %>
        <%= link_to "Switch", select_tenant_path %>
      <% end %>
    </div>
  <% end %>
</nav>
```

---

## Security Considerations

### 1. Validate Tenant Access

Always validate that the user has access to the requested tenant:

```ruby
# In before_switch callback
config.before_switch do |from, to|
  next unless to && defined?(Current) && Current.user
  raise "Access denied" unless Current.user.has_access_to?(to)
end
```

### 2. Prevent Tenant Enumeration

Don't reveal whether a tenant exists:

```ruby
# Bad - reveals tenant existence
if !tenant_exists?(params[:tenant])
  render json: { error: "Tenant not found" }
end

# Good - generic error
if !user.has_access_to?(params[:tenant])
  render json: { error: "Access denied" }, status: :forbidden
end
```

### 3. Session Fixation Protection

Reset session on login:

```ruby
def create
  if user&.authenticate(params[:password])
    reset_session  # Prevent session fixation
    session[:user_id] = user.id
    # ...
  end
end
```

### 4. Cross-Tenant Data Leakage

Always verify tenant context before showing data:

```ruby
def show
  @article = Article.find(params[:id])

  # This is already handled by BetterTenant's default scope
  # But for extra safety with unscoped queries:
  unless @article.tenant_id == BetterTenant::Tenant.current
    raise ActiveRecord::RecordNotFound
  end
end
```

---

## Devise Integration

### Configuration

```ruby
# config/initializers/devise.rb
Devise.setup do |config|
  # ... other config

  # Disable scoped views if using single User model
  config.scoped_views = false
end
```

### Custom Sessions Controller

```ruby
# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  def create
    super do |user|
      # After successful login, set tenant
      if user.tenants.count == 1
        session[:current_tenant_id] = user.default_tenant
      elsif user.tenants.count > 1
        # Will be redirected to tenant selector
        stored_location_for(user) || select_tenant_path
      end
    end
  end

  def destroy
    session.delete(:current_tenant_id)
    super
  end

  protected

  def after_sign_in_path_for(resource)
    if resource.tenants.count > 1 && session[:current_tenant_id].blank?
      select_tenant_path
    else
      super
    end
  end
end
```

### Routes

```ruby
# config/routes.rb
devise_for :users, controllers: {
  sessions: "users/sessions"
}
```

---

## Testing

### Login Flow

```ruby
# spec/requests/login_spec.rb
RSpec.describe "Login flow" do
  let(:user) { create(:user) }
  let!(:membership) { create(:membership, user: user, tenant_id: "acme") }

  before do
    BetterTenant.configure do |config|
      config.strategy :column
      config.tenant_names %w[acme globex]
      config.require_tenant false
    end
  end

  it "sets tenant after login" do
    post login_path, params: { email: user.email, password: "password" }

    expect(session[:current_tenant_id]).to eq("acme")
    expect(response).to redirect_to(root_path)
  end

  it "shows selector for multi-tenant users" do
    create(:membership, user: user, tenant_id: "globex")

    post login_path, params: { email: user.email, password: "password" }

    expect(response).to redirect_to(select_tenant_path)
  end
end
```

### Tenant Switching

```ruby
# spec/requests/tenant_switching_spec.rb
RSpec.describe "Tenant switching" do
  let(:user) { create(:user) }
  let!(:acme) { create(:membership, user: user, tenant_id: "acme") }
  let!(:globex) { create(:membership, user: user, tenant_id: "globex") }

  before do
    post login_path, params: { email: user.email, password: "password" }
  end

  it "switches tenant" do
    post switch_tenant_path, params: { tenant_id: "globex" }

    expect(session[:current_tenant_id]).to eq("globex")
  end

  it "prevents switching to unauthorized tenant" do
    post switch_tenant_path, params: { tenant_id: "unknown" }

    expect(response).to redirect_to(select_tenant_path)
    expect(flash[:alert]).to eq("Access denied")
  end
end
```

### Unauthorized Access

```ruby
# spec/requests/authorization_spec.rb
RSpec.describe "Tenant authorization" do
  let(:user) { create(:user) }
  let!(:membership) { create(:membership, user: user, tenant_id: "acme") }

  before do
    post login_path, params: { email: user.email, password: "password" }
    post switch_tenant_path, params: { tenant_id: "acme" }
  end

  it "prevents access to other tenant data" do
    other_article = create(:article, tenant_id: "globex", title: "Secret")

    expect {
      get article_path(other_article)
    }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
```

---

## Common Patterns

### Remember Last Tenant

```ruby
def switch
  tenant_id = params[:tenant_id]

  if Current.user.has_access_to?(tenant_id)
    session[:current_tenant_id] = tenant_id

    # Remember for next login
    Current.user.update(last_tenant_id: tenant_id)

    redirect_to root_path
  end
end

# In sessions_controller
def set_tenant_after_login(user)
  if user.last_tenant_id && user.has_access_to?(user.last_tenant_id)
    session[:current_tenant_id] = user.last_tenant_id
  else
    session[:current_tenant_id] = user.default_tenant
  end
end
```

### Invite User to Tenant

```ruby
class InvitationsController < ApplicationController
  def create
    user = User.find_or_initialize_by(email: params[:email])

    if user.new_record?
      user.save!
      # Send invitation email
    end

    Membership.create!(
      user: user,
      tenant_id: BetterTenant::Tenant.current,
      role: params[:role] || "member"
    )

    redirect_to members_path, notice: "User invited"
  end
end
```

### API with Session (Same-Origin)

For SPAs on the same domain:

```ruby
class Api::BaseController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_user!

  private

  def authenticate_api_user!
    # Session already set by middleware
    return if Current.user && BetterTenant::Tenant.current

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
```

---

## Summary

1. **Database**: Create `memberships` table for user-tenant mapping
2. **Config**: Set `require_tenant false` to allow login page
3. **Middleware**: Use Proc that reads `session[:current_tenant_id]`
4. **Login**: Set session after authentication
5. **Selector**: Show tenant picker for multi-tenant users
6. **Security**: Validate access in `before_switch` callback
