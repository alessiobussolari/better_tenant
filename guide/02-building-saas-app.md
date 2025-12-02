# Building a SaaS App

A complete tutorial for building a multi-tenant SaaS application with column strategy.

---

## What You'll Build

A simple project management SaaS where each organization (tenant) has their own projects and tasks. We'll use:

- Column strategy with `organization_id`
- Subdomain-based tenant detection
- Dynamic tenant loading from database

## Prerequisites

- Completed [Quick Start](01-quick-start.md)
- Basic understanding of Rails

## Step 1: Create the Rails App

```bash
rails new project_hub --database=postgresql
cd project_hub
bundle add better_tenant
```

## Step 2: Create Organizations Model

```bash
rails generate model Organization name:string subdomain:string
rails db:migrate
```

```ruby
# app/models/organization.rb
class Organization < ApplicationRecord
  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true

  # Subdomain format validation
  validates :subdomain, format: {
    with: /\A[a-z][a-z0-9-]*\z/,
    message: "must start with letter, only lowercase and hyphens"
  }
end
```

## Step 3: Configure BetterTenant

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :organization_id

  # Dynamic tenant names from database
  config.tenant_model "Organization"
  config.tenant_identifier :subdomain

  # Optional: elevator configuration
  config.elevator :subdomain
  config.excluded_subdomains %w[www admin api]

  # Require tenant for most operations
  config.require_tenant true
end
```

## Step 4: Create Tenanted Models

### Projects

```bash
rails generate model Project name:string description:text organization_id:string
```

```ruby
# app/models/project.rb
class Project < ApplicationRecord
  include BetterTenant::ActiveRecordExtension

  has_many :tasks, dependent: :destroy

  validates :name, presence: true
end
```

### Tasks

```bash
rails generate model Task title:string completed:boolean project:references organization_id:string
```

```ruby
# app/models/task.rb
class Task < ApplicationRecord
  include BetterTenant::ActiveRecordExtension

  belongs_to :project

  validates :title, presence: true

  scope :completed, -> { where(completed: true) }
  scope :pending, -> { where(completed: false) }
end
```

### Run migrations

```bash
rails db:migrate
```

Add indexes for performance:

```ruby
# db/migrate/xxx_add_organization_indexes.rb
class AddOrganizationIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :projects, :organization_id
    add_index :tasks, :organization_id
    add_index :tasks, [:organization_id, :completed]
  end
end
```

## Step 5: Add Middleware

```ruby
# config/application.rb
module ProjectHub
  class Application < Rails::Application
    # ...

    # Subdomain-based tenant detection
    config.middleware.use BetterTenant::Middleware, :subdomain
  end
end
```

## Step 6: Create Controllers

### Application Controller

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  rescue_from BetterTenant::Errors::TenantNotFoundError do |e|
    render status: :not_found, plain: "Organization not found"
  end

  rescue_from BetterTenant::Errors::TenantContextMissingError do |e|
    redirect_to root_url(subdomain: "www")
  end

  helper_method :current_organization

  private

  def current_organization
    return @current_organization if defined?(@current_organization)

    subdomain = BetterTenant::Tenant.current
    @current_organization = Organization.find_by(subdomain: subdomain) if subdomain
  end
end
```

### Projects Controller

```ruby
# app/controllers/projects_controller.rb
class ProjectsController < ApplicationController
  def index
    @projects = Project.all
  end

  def show
    @project = Project.find(params[:id])
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      redirect_to @project, notice: "Project created!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @project = Project.find(params[:id])
    @project.destroy
    redirect_to projects_path, notice: "Project deleted!"
  end

  private

  def project_params
    params.require(:project).permit(:name, :description)
  end
end
```

### Tasks Controller

```ruby
# app/controllers/tasks_controller.rb
class TasksController < ApplicationController
  before_action :set_project
  before_action :set_task, only: [:toggle, :destroy]

  def create
    @task = @project.tasks.new(task_params)

    if @task.save
      redirect_to @project, notice: "Task added!"
    else
      redirect_to @project, alert: "Could not add task"
    end
  end

  def toggle
    @task.update(completed: !@task.completed)
    redirect_to @project
  end

  def destroy
    @task.destroy
    redirect_to @project, notice: "Task deleted!"
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_task
    @task = @project.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title)
  end
end
```

## Step 7: Setup Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  constraints(subdomain: /(?!www|admin|api).+/) do
    resources :projects do
      resources :tasks, only: [:create, :destroy] do
        member do
          patch :toggle
        end
      end
    end

    root "projects#index"
  end

  # Landing page for www subdomain
  constraints(subdomain: ["", "www"]) do
    root "home#index", as: :landing
  end
end
```

## Step 8: Seed Data

```ruby
# db/seeds.rb
# Create organizations
acme = Organization.create!(name: "Acme Corp", subdomain: "acme")
globex = Organization.create!(name: "Globex Inc", subdomain: "globex")

# Seed Acme data
BetterTenant::Tenant.switch(acme.subdomain) do
  project = Project.create!(name: "Website Redesign")
  project.tasks.create!(title: "Design mockups")
  project.tasks.create!(title: "Implement frontend")
  project.tasks.create!(title: "Deploy to production")
end

# Seed Globex data
BetterTenant::Tenant.switch(globex.subdomain) do
  project = Project.create!(name: "Mobile App")
  project.tasks.create!(title: "Setup React Native")
  project.tasks.create!(title: "Build authentication")
end

puts "Seeded #{Organization.count} organizations"
```

```bash
rails db:seed
```

## Step 9: Configure Local Development

For subdomain testing locally:

```ruby
# config/environments/development.rb
config.hosts << ".lvh.me"
```

Access your app at:
- `http://acme.lvh.me:3000` - Acme's projects
- `http://globex.lvh.me:3000` - Globex's projects

## Testing Your Implementation

```ruby
# spec/models/project_spec.rb
require "rails_helper"

RSpec.describe Project do
  before do
    Organization.create!(name: "Test", subdomain: "test")
  end

  it "scopes to current tenant", :tenant do
    BetterTenant::Tenant.switch("test") do
      Project.create!(name: "Test Project")
      expect(Project.count).to eq(1)
    end
  end

  it "isolates tenant data" do
    Organization.create!(name: "Other", subdomain: "other")

    BetterTenant::Tenant.switch("test") do
      Project.create!(name: "Test Project")
    end

    BetterTenant::Tenant.switch("other") do
      expect(Project.count).to eq(0)
    end
  end
end
```

## Summary

In this guide, you learned how to:

- Configure column strategy with dynamic tenant names
- Create tenanted models with automatic scoping
- Setup subdomain-based tenant detection
- Build controllers that work within tenant context
- Test tenant isolation

## Next Steps

- [Building Multi-Tenant API](03-building-multi-tenant-api.md) - Schema strategy with API
- [ActiveJob Integration](../docs/06-activejob.md) - Background jobs
- [Configuration Options](../docs/02-configuration.md) - Advanced configuration
