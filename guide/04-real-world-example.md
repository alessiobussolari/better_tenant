# Real World Example

A complete example implementing a multi-tenant CRM with BetterTenant.

---

## Overview

This guide walks through building a complete multi-tenant CRM application using all features of BetterTenant.

## The Application

We'll build a CRM with:

- Organizations (tenants) with subdomain access
- Contacts and Companies management
- Deals pipeline
- Activities tracking
- Background job processing
- Admin panel for cross-tenant operations

## Project Setup

```bash
rails new better_crm --database=postgresql
cd better_crm
bundle add better_tenant
bundle add devise  # For authentication
bundle install
```

## Part 1: Database Structure

### 1.1 Create Organizations

```ruby
# db/migrate/xxx_create_organizations.rb
class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :subdomain, null: false
      t.string :plan, default: "free"  # free, pro, enterprise
      t.integer :seats_limit, default: 5
      t.datetime :trial_ends_at

      t.timestamps
    end

    add_index :organizations, :subdomain, unique: true
  end
end
```

### 1.2 Create Users (Public Schema)

```ruby
# db/migrate/xxx_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :encrypted_password, null: false
      t.string :name
      t.references :organization, null: false, foreign_key: true
      t.string :role, default: "member"  # admin, manager, member

      # Devise fields
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
  end
end
```

### 1.3 Create Tenanted Tables

```ruby
# db/migrate/xxx_create_contacts.rb
class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email
      t.string :phone
      t.string :organization_id, null: false  # tenant column
      t.references :company, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :contacts, :organization_id
    add_index :contacts, [:organization_id, :email]
  end
end

# db/migrate/xxx_create_companies.rb
class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :website
      t.string :industry
      t.string :organization_id, null: false

      t.timestamps
    end

    add_index :companies, :organization_id
  end
end

# db/migrate/xxx_create_deals.rb
class CreateDeals < ActiveRecord::Migration[8.1]
  def change
    create_table :deals do |t|
      t.string :name, null: false
      t.decimal :value, precision: 15, scale: 2
      t.string :stage, default: "lead"  # lead, qualified, proposal, won, lost
      t.string :organization_id, null: false
      t.references :contact, foreign_key: true
      t.references :company, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.date :expected_close_date

      t.timestamps
    end

    add_index :deals, :organization_id
    add_index :deals, [:organization_id, :stage]
  end
end

# db/migrate/xxx_create_activities.rb
class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.string :type, null: false  # call, email, meeting, note
      t.text :description
      t.string :organization_id, null: false
      t.references :contact, foreign_key: true
      t.references :deal, foreign_key: true
      t.references :user, foreign_key: true
      t.datetime :scheduled_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :activities, :organization_id
    add_index :activities, [:organization_id, :type]
  end
end
```

Run migrations:

```bash
rails db:migrate
```

## Part 2: Models

### 2.1 Organization Model

```ruby
# app/models/organization.rb
class Organization < ApplicationRecord
  has_many :users, dependent: :destroy

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
    format: { with: /\A[a-z][a-z0-9-]*\z/, message: "must be lowercase" }

  def trial_active?
    trial_ends_at.present? && trial_ends_at > Time.current
  end

  def seats_available?
    users.count < seats_limit
  end
end
```

### 2.2 User Model

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  belongs_to :organization

  validates :name, presence: true
  validates :role, inclusion: { in: %w[admin manager member] }

  def admin?
    role == "admin"
  end

  def can_manage?(resource)
    admin? || resource.owner_id == id
  end
end
```

### 2.3 Base Tenanted Model

```ruby
# app/models/tenant_record.rb
class TenantRecord < ApplicationRecord
  self.abstract_class = true
  include BetterTenant::ActiveRecordExtension
end
```

### 2.4 Tenanted Models

```ruby
# app/models/contact.rb
class Contact < TenantRecord
  belongs_to :company, optional: true
  belongs_to :owner, class_name: "User", optional: true
  has_many :deals, dependent: :nullify
  has_many :activities, dependent: :destroy

  validates :first_name, :last_name, presence: true

  def full_name
    "#{first_name} #{last_name}"
  end
end

# app/models/company.rb
class Company < TenantRecord
  has_many :contacts, dependent: :nullify
  has_many :deals, dependent: :nullify

  validates :name, presence: true
end

# app/models/deal.rb
class Deal < TenantRecord
  STAGES = %w[lead qualified proposal negotiation won lost].freeze

  belongs_to :contact, optional: true
  belongs_to :company, optional: true
  belongs_to :owner, class_name: "User", optional: true
  has_many :activities, dependent: :destroy

  validates :name, presence: true
  validates :stage, inclusion: { in: STAGES }

  scope :open, -> { where.not(stage: %w[won lost]) }
  scope :won, -> { where(stage: "won") }
  scope :by_stage, ->(stage) { where(stage: stage) }

  def closed?
    %w[won lost].include?(stage)
  end
end

# app/models/activity.rb
class Activity < TenantRecord
  TYPES = %w[call email meeting note task].freeze

  belongs_to :contact, optional: true
  belongs_to :deal, optional: true
  belongs_to :user

  validates :type, inclusion: { in: TYPES }

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :overdue, -> { where("scheduled_at < ? AND completed_at IS NULL", Time.current) }
end
```

## Part 3: Configuration

### 3.1 BetterTenant Configuration

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :organization_id

  # Dynamic from database
  config.tenant_model "Organization"
  config.tenant_identifier :subdomain

  # Users/Organizations in public
  config.excluded_models %w[Organization User]

  # Subdomain elevator
  config.elevator :subdomain
  config.excluded_subdomains %w[www admin api app]

  # Require tenant for CRM operations
  config.require_tenant true

  # Logging
  config.after_switch do |from, to|
    Rails.logger.info "[CRM] Tenant: #{from || 'public'} -> #{to || 'public'}"
  end
end
```

### 3.2 Middleware

```ruby
# config/application.rb
module BetterCrm
  class Application < Rails::Application
    config.middleware.use BetterTenant::Middleware, :subdomain
  end
end
```

## Part 4: Controllers

### 4.1 Application Controller

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_tenant_context

  rescue_from BetterTenant::Errors::TenantNotFoundError, with: :tenant_not_found
  rescue_from BetterTenant::Errors::TenantContextMissingError, with: :tenant_required

  helper_method :current_organization

  private

  def set_tenant_context
    return unless user_signed_in?

    # Verify user belongs to current tenant
    tenant = BetterTenant::Tenant.current
    if tenant && current_user.organization.subdomain != tenant
      sign_out current_user
      redirect_to root_path, alert: "Access denied"
    end
  end

  def current_organization
    @current_organization ||= current_user&.organization
  end

  def tenant_not_found
    redirect_to landing_url(subdomain: "www"), alert: "Organization not found"
  end

  def tenant_required
    redirect_to landing_url(subdomain: "www")
  end
end
```

### 4.2 Dashboard Controller

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def index
    @stats = {
      contacts_count: Contact.count,
      companies_count: Company.count,
      open_deals_count: Deal.open.count,
      open_deals_value: Deal.open.sum(:value),
      won_deals_count: Deal.won.count,
      won_deals_value: Deal.won.sum(:value)
    }

    @recent_activities = Activity.includes(:user, :contact, :deal)
                                  .order(created_at: :desc)
                                  .limit(10)

    @upcoming_activities = Activity.upcoming.includes(:contact, :deal).limit(5)
  end
end
```

### 4.3 Contacts Controller

```ruby
# app/controllers/contacts_controller.rb
class ContactsController < ApplicationController
  def index
    @contacts = Contact.includes(:company, :owner)
                       .order(created_at: :desc)
                       .page(params[:page])
  end

  def show
    @contact = Contact.find(params[:id])
    @activities = @contact.activities.includes(:user).recent
    @deals = @contact.deals.includes(:company)
  end

  def new
    @contact = Contact.new
  end

  def create
    @contact = Contact.new(contact_params)
    @contact.owner = current_user

    if @contact.save
      redirect_to @contact, notice: "Contact created!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contact = Contact.find(params[:id])
  end

  def update
    @contact = Contact.find(params[:id])

    if @contact.update(contact_params)
      redirect_to @contact, notice: "Contact updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact = Contact.find(params[:id])
    @contact.destroy
    redirect_to contacts_path, notice: "Contact deleted!"
  end

  private

  def contact_params
    params.require(:contact).permit(:first_name, :last_name, :email, :phone, :company_id)
  end
end
```

## Part 5: Background Jobs

### 5.1 Activity Reminder Job

```ruby
# app/jobs/activity_reminder_job.rb
class ActivityReminderJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(activity_id)
    activity = Activity.find(activity_id)
    return if activity.completed_at.present?

    ActivityMailer.reminder(activity).deliver_now
  end
end
```

### 5.2 Daily Report Job

```ruby
# app/jobs/daily_report_job.rb
class DailyReportJob < ApplicationJob
  def perform
    # Run for each tenant
    BetterTenant::Tenant.each do |tenant|
      GenerateTenantReportJob.perform_later(tenant)
    end
  end
end

class GenerateTenantReportJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform
    # Runs in tenant context
    admins = User.where(role: "admin")

    report_data = {
      new_contacts: Contact.where("created_at > ?", 1.day.ago).count,
      deals_won: Deal.won.where("updated_at > ?", 1.day.ago).sum(:value),
      activities_completed: Activity.where("completed_at > ?", 1.day.ago).count
    }

    admins.each do |admin|
      ReportMailer.daily_summary(admin, report_data).deliver_now
    end
  end
end
```

## Part 6: Admin Panel (Cross-Tenant)

### 6.1 Admin Controller

```ruby
# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ActionController::Base
    before_action :require_super_admin

    private

    def require_super_admin
      # Custom authentication for super admins
      authenticate_or_request_with_http_basic do |username, password|
        username == ENV["ADMIN_USER"] && password == ENV["ADMIN_PASSWORD"]
      end
    end
  end
end

# app/controllers/admin/organizations_controller.rb
module Admin
  class OrganizationsController < BaseController
    def index
      @organizations = Organization.all.includes(:users)
    end

    def show
      @organization = Organization.find(params[:id])

      # Access tenant data
      BetterTenant::Tenant.switch(@organization.subdomain) do
        @stats = {
          contacts: Contact.count,
          companies: Company.count,
          deals: Deal.count,
          activities: Activity.count
        }
      end
    end
  end
end
```

## Running the Application

```bash
rails server
```

Access tenants at:
- `http://acme.lvh.me:3000` - Acme CRM
- `http://globex.lvh.me:3000` - Globex CRM
- `http://admin.lvh.me:3000/admin` - Admin panel

## Full Source Code

The complete source code for this example is available at:
[https://github.com/alessiobussolari/better_crm-example](https://github.com/alessiobussolari/better_crm-example)
