# Building Multi-Tenant API

A complete tutorial for building a multi-tenant REST API with schema strategy.

---

## What You'll Build

A multi-tenant REST API for a notes application where each tenant has completely isolated data in PostgreSQL schemas. We'll use:

- Schema strategy with PostgreSQL
- Header-based tenant detection (X-Tenant)
- JWT authentication with tenant context
- API-only Rails application

## Prerequisites

- PostgreSQL installed
- Completed [Quick Start](01-quick-start.md)
- Basic understanding of REST APIs

## Step 1: Create the API App

```bash
rails new notes_api --api --database=postgresql
cd notes_api
bundle add better_tenant
bundle add jwt
bundle add bcrypt
```

## Step 2: Create Tenants Model

```bash
rails generate model Tenant name:string api_key:string:uniq
rails db:migrate
```

```ruby
# app/models/tenant.rb
class Tenant < ApplicationRecord
  has_secure_token :api_key

  validates :name, presence: true, uniqueness: true
  validates :name, format: {
    with: /\A[a-z][a-z0-9_]*\z/,
    message: "must be lowercase letters, numbers, and underscores"
  }
end
```

## Step 3: Configure BetterTenant

```ruby
# config/initializers/better_tenant.rb
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_model "Tenant"
  config.tenant_identifier :name

  # Models in public schema
  config.excluded_models %w[Tenant User]

  # Schema naming
  config.schema_format "tenant_%{tenant}"

  # Header-based detection
  config.elevator :header

  # API should require tenant
  config.require_tenant true

  # Callbacks for tenant lifecycle
  config.after_create do |tenant|
    # Seed initial data for new tenant
    Category.create!(name: "General")
    Category.create!(name: "Work")
    Category.create!(name: "Personal")
  end
end
```

## Step 4: Create Tenanted Models

### Categories

```bash
rails generate model Category name:string
```

```ruby
# app/models/category.rb
class Category < ApplicationRecord
  has_many :notes, dependent: :destroy

  validates :name, presence: true
end
```

### Notes

```bash
rails generate model Note title:string content:text category:references
```

```ruby
# app/models/note.rb
class Note < ApplicationRecord
  belongs_to :category

  validates :title, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
```

Run migrations:

```bash
rails db:migrate
```

## Step 5: Create Users Model (Public Schema)

```ruby
# db/migrate/xxx_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # Ensure we're in public schema
    execute "SET search_path TO public"

    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :tenant_name, null: false  # Which tenant user belongs to

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :tenant_name

    execute "RESET search_path"
  end
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password

  belongs_to :tenant, foreign_key: :tenant_name, primary_key: :name

  validates :email, presence: true, uniqueness: true
  validates :tenant_name, presence: true
end
```

## Step 6: Add Middleware

```ruby
# config/application.rb
module NotesApi
  class Application < Rails::Application
    config.api_only = true

    # Header-based tenant detection
    config.middleware.use BetterTenant::Middleware, :header
  end
end
```

## Step 7: Create API Controllers

### Application Controller

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  rescue_from BetterTenant::Errors::TenantNotFoundError do |e|
    render json: { error: "Tenant not found" }, status: :not_found
  end

  rescue_from BetterTenant::Errors::TenantContextMissingError do |e|
    render json: { error: "X-Tenant header required" }, status: :bad_request
  end

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: "Resource not found" }, status: :not_found
  end
end
```

### Tenants Controller (Admin)

```ruby
# app/controllers/api/v1/tenants_controller.rb
module Api
  module V1
    class TenantsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/tenants
      def create
        tenant = Tenant.new(tenant_params)

        if tenant.save
          # Create the schema
          BetterTenant::Tenant.create(tenant.name)

          render json: {
            tenant: {
              name: tenant.name,
              api_key: tenant.api_key
            }
          }, status: :created
        else
          render json: { errors: tenant.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def tenant_params
        params.require(:tenant).permit(:name)
      end
    end
  end
end
```

### Categories Controller

```ruby
# app/controllers/api/v1/categories_controller.rb
module Api
  module V1
    class CategoriesController < ApplicationController
      def index
        categories = Category.all
        render json: { categories: categories }
      end

      def show
        category = Category.find(params[:id])
        render json: { category: category, notes: category.notes }
      end

      def create
        category = Category.new(category_params)

        if category.save
          render json: { category: category }, status: :created
        else
          render json: { errors: category.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        category = Category.find(params[:id])
        category.destroy
        head :no_content
      end

      private

      def category_params
        params.require(:category).permit(:name)
      end
    end
  end
end
```

### Notes Controller

```ruby
# app/controllers/api/v1/notes_controller.rb
module Api
  module V1
    class NotesController < ApplicationController
      def index
        notes = Note.recent.includes(:category)
        render json: { notes: notes.as_json(include: :category) }
      end

      def show
        note = Note.find(params[:id])
        render json: { note: note.as_json(include: :category) }
      end

      def create
        note = Note.new(note_params)

        if note.save
          render json: { note: note }, status: :created
        else
          render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        note = Note.find(params[:id])

        if note.update(note_params)
          render json: { note: note }
        else
          render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        note = Note.find(params[:id])
        note.destroy
        head :no_content
      end

      private

      def note_params
        params.require(:note).permit(:title, :content, :category_id)
      end
    end
  end
end
```

## Step 8: Setup Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # Admin routes (no tenant required)
      resources :tenants, only: [:create]

      # Tenant-scoped routes
      resources :categories, only: [:index, :show, :create, :destroy]
      resources :notes
    end
  end
end
```

## Step 9: Test the API

### Create a Tenant

```bash
curl -X POST http://localhost:3000/api/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{"tenant": {"name": "acme"}}'

# Response:
# {"tenant": {"name": "acme", "api_key": "xxx..."}}
```

### Use the API with Tenant

```bash
# List categories
curl http://localhost:3000/api/v1/categories \
  -H "X-Tenant: acme"

# Create a note
curl -X POST http://localhost:3000/api/v1/notes \
  -H "Content-Type: application/json" \
  -H "X-Tenant: acme" \
  -d '{"note": {"title": "My Note", "content": "Hello!", "category_id": 1}}'

# Get notes
curl http://localhost:3000/api/v1/notes \
  -H "X-Tenant: acme"
```

### Verify Isolation

```bash
# Create another tenant
curl -X POST http://localhost:3000/api/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{"tenant": {"name": "globex"}}'

# Globex sees no notes (different schema)
curl http://localhost:3000/api/v1/notes \
  -H "X-Tenant: globex"

# Response: {"notes": []}
```

## Step 10: Add Background Jobs

```ruby
# app/jobs/note_export_job.rb
class NoteExportJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(email)
    # Automatically runs in correct tenant context
    notes = Note.all

    # Generate export
    csv = notes.map { |n| "#{n.title},#{n.content}" }.join("\n")

    # Send email
    ExportMailer.notes_export(email, csv).deliver_now
  end
end
```

```ruby
# Usage in controller
def export
  NoteExportJob.perform_later(params[:email])
  render json: { message: "Export started" }
end
```

## Testing

```ruby
# spec/requests/api/v1/notes_spec.rb
require "rails_helper"

RSpec.describe "Notes API" do
  let!(:tenant) { Tenant.create!(name: "test") }

  before do
    BetterTenant::Tenant.create(tenant.name)
  end

  describe "GET /api/v1/notes" do
    it "returns tenant's notes" do
      BetterTenant::Tenant.switch(tenant.name) do
        category = Category.create!(name: "Test")
        Note.create!(title: "Test Note", category: category)
      end

      get "/api/v1/notes", headers: { "X-Tenant" => tenant.name }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["notes"].length).to eq(1)
    end

    it "requires tenant header" do
      get "/api/v1/notes"

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects invalid tenant" do
      get "/api/v1/notes", headers: { "X-Tenant" => "invalid" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
```

## Summary

In this guide, you learned how to:

- Configure schema strategy with PostgreSQL
- Use header-based tenant detection for APIs
- Create tenant schemas programmatically
- Build RESTful controllers for multi-tenant API
- Test API with different tenants

## Next Steps

- [Real World Example](04-real-world-example.md) - Complete CRM application
- [Callbacks](../docs/07-callbacks.md) - Lifecycle hooks
- [API Reference](../docs/08-api-reference.md) - Complete API documentation
