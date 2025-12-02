# Testing

Guide for testing multi-tenant Rails applications with BetterTenant.

---

## Overview

Testing multi-tenant applications requires special consideration for:
- Setting up tenant context before tests
- Cleaning up between tests
- Testing both strategies (column and schema)
- Testing middleware and background jobs

## RSpec Setup

### Basic Configuration

Add to `spec/rails_helper.rb`:

```ruby
require "better_tenant"

RSpec.configure do |config|
  # Reset BetterTenant before each test
  config.before(:each) do
    BetterTenant.reset!
  end

  # Ensure tenant is reset after each test
  config.after(:each) do
    BetterTenant::Tenant.reset rescue nil
  end
end
```

### Helper Module

Create `spec/support/better_tenant_helpers.rb`:

```ruby
module BetterTenantHelpers
  # Switch to a tenant for the duration of the block
  def with_tenant(tenant, &block)
    BetterTenant::Tenant.switch(tenant, &block)
  end

  # Configure BetterTenant for column strategy
  def configure_column_strategy(tenants: %w[acme globex])
    BetterTenant.configure do |config|
      config.strategy :column
      config.tenant_column :tenant_id
      config.tenant_names tenants
      config.require_tenant false
    end
  end

  # Configure BetterTenant for schema strategy
  def configure_schema_strategy(tenants: %w[acme globex])
    BetterTenant.configure do |config|
      config.strategy :schema
      config.tenant_names tenants
      config.schema_format "tenant_%{tenant}"
      config.require_tenant false
    end
  end

  # Create a tenant (schema strategy)
  def create_tenant_schema(tenant)
    BetterTenant::Tenant.create(tenant)
  end

  # Drop a tenant (schema strategy)
  def drop_tenant_schema(tenant)
    BetterTenant::Tenant.drop(tenant)
  end
end

RSpec.configure do |config|
  config.include BetterTenantHelpers
end
```

## Testing Column Strategy

### Model Tests

```ruby
# spec/models/article_spec.rb
require "rails_helper"

RSpec.describe Article, type: :model do
  before do
    configure_column_strategy(tenants: %w[acme globex])
  end

  describe "tenant scoping" do
    it "automatically sets tenant_id on create" do
      with_tenant("acme") do
        article = Article.create!(title: "Test")
        expect(article.tenant_id).to eq("acme")
      end
    end

    it "scopes queries to current tenant" do
      # Create articles in different tenants
      with_tenant("acme") do
        Article.create!(title: "Acme Article")
      end
      with_tenant("globex") do
        Article.create!(title: "Globex Article")
      end

      # Verify scoping
      with_tenant("acme") do
        expect(Article.count).to eq(1)
        expect(Article.first.title).to eq("Acme Article")
      end
    end

    it "prevents cross-tenant access" do
      with_tenant("acme") do
        article = Article.create!(title: "Acme Article")

        # Switch to different tenant
        with_tenant("globex") do
          expect(Article.find_by(id: article.id)).to be_nil
        end
      end
    end
  end

  describe "unscoped_tenant" do
    it "allows cross-tenant queries" do
      with_tenant("acme") { Article.create!(title: "A") }
      with_tenant("globex") { Article.create!(title: "B") }

      with_tenant("acme") do
        Article.unscoped_tenant do
          expect(Article.count).to eq(2)
        end
      end
    end
  end
end
```

### Strict Mode Tests

```ruby
RSpec.describe "Strict mode" do
  before do
    BetterTenant.configure do |config|
      config.strategy :column
      config.tenant_column :tenant_id
      config.tenant_names %w[acme globex]
      config.strict_mode true
    end
  end

  it "prevents changing tenant_id" do
    with_tenant("acme") do
      article = Article.create!(title: "Test")

      expect {
        article.update!(tenant_id: "globex")
      }.to raise_error(BetterTenant::Errors::TenantImmutableError)
    end
  end
end
```

## Testing Schema Strategy

### Setup and Teardown

```ruby
# spec/support/schema_strategy_helpers.rb
module SchemaStrategyHelpers
  def setup_schema_strategy
    configure_schema_strategy(tenants: %w[test_acme test_globex])

    # Create schemas
    %w[test_acme test_globex].each do |tenant|
      create_tenant_schema(tenant) unless BetterTenant::Tenant.exists?(tenant)
    end
  end

  def teardown_schema_strategy
    %w[test_acme test_globex].each do |tenant|
      drop_tenant_schema(tenant) rescue nil
    end
  end
end

RSpec.configure do |config|
  config.include SchemaStrategyHelpers, schema_strategy: true

  config.before(:suite) do
    # Setup schemas once for all tests
  end

  config.after(:suite) do
    # Cleanup schemas
  end
end
```

### Schema Strategy Tests

```ruby
# spec/integration/schema_strategy_spec.rb
require "rails_helper"

RSpec.describe "Schema Strategy", schema_strategy: true do
  before(:all) do
    setup_schema_strategy
  end

  after(:all) do
    teardown_schema_strategy
  end

  before(:each) do
    BetterTenant::Tenant.reset
  end

  describe "tenant isolation" do
    it "creates tables in tenant schema" do
      with_tenant("test_acme") do
        # Run migration in tenant context
        Article.create!(title: "Test")
        expect(Article.count).to eq(1)
      end

      with_tenant("test_globex") do
        expect(Article.count).to eq(0)
      end
    end

    it "switches search_path correctly" do
      with_tenant("test_acme") do
        result = ActiveRecord::Base.connection.execute("SHOW search_path").first
        expect(result["search_path"]).to include("tenant_test_acme")
      end
    end
  end

  describe "schema creation" do
    it "creates schema with correct name" do
      expect(BetterTenant::Tenant.exists?("test_acme")).to be true
    end
  end
end
```

## Testing Middleware

### Request Specs

```ruby
# spec/requests/tenant_middleware_spec.rb
require "rails_helper"

RSpec.describe "Tenant Middleware", type: :request do
  before do
    configure_column_strategy(tenants: %w[acme globex])
  end

  describe "subdomain elevator" do
    before do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_names %w[acme globex]
        config.elevator :subdomain
      end
    end

    it "extracts tenant from subdomain" do
      host! "acme.example.com"
      get "/articles"

      expect(response).to have_http_status(:success)
      # Verify tenant was set (depends on your application)
    end

    it "excludes www subdomain" do
      host! "www.example.com"
      get "/articles"

      # Should work without tenant context
      expect(response).to have_http_status(:success)
    end
  end

  describe "header elevator" do
    before do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_names %w[acme globex]
        config.elevator :header
      end
    end

    it "extracts tenant from X-Tenant header" do
      get "/articles", headers: { "X-Tenant" => "acme" }
      expect(response).to have_http_status(:success)
    end

    it "returns error for invalid tenant" do
      expect {
        get "/articles", headers: { "X-Tenant" => "invalid" }
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end
  end

  describe "path elevator" do
    before do
      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_names %w[acme globex]
        config.elevator :path
      end
    end

    it "extracts tenant from path" do
      get "/acme/articles"
      expect(response).to have_http_status(:success)
    end
  end
end
```

### Controller Tests

```ruby
# spec/controllers/articles_controller_spec.rb
require "rails_helper"

RSpec.describe ArticlesController, type: :controller do
  before do
    configure_column_strategy(tenants: %w[acme])
    BetterTenant::Tenant.switch!("acme")
  end

  after do
    BetterTenant::Tenant.reset
  end

  describe "GET #index" do
    it "returns tenant-scoped articles" do
      article = Article.create!(title: "Test", tenant_id: "acme")

      get :index

      expect(assigns(:articles)).to include(article)
    end
  end
end
```

## Testing ActiveJob

### Job Tests

```ruby
# spec/jobs/process_order_job_spec.rb
require "rails_helper"

RSpec.describe ProcessOrderJob, type: :job do
  before do
    configure_column_strategy(tenants: %w[acme])
  end

  describe "tenant serialization" do
    it "captures tenant at enqueue time" do
      with_tenant("acme") do
        job = ProcessOrderJob.new(123)
        expect(job.tenant_for_job).to eq("acme")
      end
    end

    it "serializes tenant in job data" do
      with_tenant("acme") do
        job = ProcessOrderJob.new(123)
        serialized = job.serialize

        expect(serialized["tenant_for_job"]).to eq("acme")
      end
    end

    it "deserializes and restores tenant" do
      with_tenant("acme") do
        job = ProcessOrderJob.new(123)
        serialized = job.serialize

        # Simulate job deserialization
        restored_job = ProcessOrderJob.new
        restored_job.deserialize(serialized)

        expect(restored_job.tenant_for_job).to eq("acme")
      end
    end
  end

  describe "job execution" do
    it "executes in correct tenant context" do
      order = nil

      with_tenant("acme") do
        order = Order.create!(total: 100)
        ProcessOrderJob.perform_now(order.id)

        order.reload
        expect(order.processed).to be true
      end
    end
  end
end
```

### Async Job Tests

```ruby
RSpec.describe ProcessOrderJob, type: :job do
  include ActiveJob::TestHelper

  before do
    configure_column_strategy(tenants: %w[acme])
  end

  it "enqueues job with tenant" do
    with_tenant("acme") do
      expect {
        ProcessOrderJob.perform_later(123)
      }.to have_enqueued_job(ProcessOrderJob)
        .with(123)
    end
  end

  it "performs job with correct tenant" do
    with_tenant("acme") do
      order = Order.create!(total: 100)

      perform_enqueued_jobs do
        ProcessOrderJob.perform_later(order.id)
      end

      expect(order.reload.processed).to be true
    end
  end
end
```

## Testing Callbacks

```ruby
# spec/better_tenant/callbacks_spec.rb
require "rails_helper"

RSpec.describe "Tenant callbacks" do
  describe "switch callbacks" do
    it "calls before_switch callback" do
      switches = []

      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_names %w[acme]
        config.before_switch { |from, to| switches << [from, to] }
      end

      BetterTenant::Tenant.switch("acme") { }

      expect(switches).to include([nil, "acme"])
    end

    it "calls after_switch callback" do
      switches = []

      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_names %w[acme]
        config.after_switch { |from, to| switches << [from, to] }
      end

      BetterTenant::Tenant.switch("acme") { }

      expect(switches).to include([nil, "acme"])
      expect(switches).to include(["acme", nil])
    end
  end

  describe "create callbacks" do
    it "calls before_create callback", schema_strategy: true do
      created = []

      BetterTenant.configure do |config|
        config.strategy :schema
        config.tenant_names %w[test_tenant]
        config.before_create { |t| created << "before:#{t}" }
      end

      BetterTenant::Tenant.create("test_tenant")

      expect(created).to include("before:test_tenant")
    ensure
      BetterTenant::Tenant.drop("test_tenant") rescue nil
    end

    it "calls after_create callback in tenant context", schema_strategy: true do
      seeded = false

      BetterTenant.configure do |config|
        config.strategy :schema
        config.tenant_names %w[test_tenant]
        config.after_create do |tenant|
          seeded = BetterTenant::Tenant.current == tenant
        end
      end

      BetterTenant::Tenant.create("test_tenant")

      expect(seeded).to be true
    ensure
      BetterTenant::Tenant.drop("test_tenant") rescue nil
    end
  end
end
```

## Factory Patterns

### FactoryBot Setup

```ruby
# spec/factories/articles.rb
FactoryBot.define do
  factory :article do
    title { "Sample Article" }
    content { "Lorem ipsum..." }

    # For column strategy: tenant_id is set automatically
    # but can be overridden for specific tests
    trait :for_acme do
      tenant_id { "acme" }
    end

    trait :for_globex do
      tenant_id { "globex" }
    end
  end
end
```

### Using Factories with Tenants

```ruby
RSpec.describe Article do
  before do
    configure_column_strategy(tenants: %w[acme globex])
  end

  it "creates article in current tenant" do
    with_tenant("acme") do
      article = create(:article)
      expect(article.tenant_id).to eq("acme")
    end
  end

  it "respects explicit tenant_id" do
    # Without tenant context, explicit tenant_id works
    article = create(:article, :for_globex)
    expect(article.tenant_id).to eq("globex")
  end
end
```

## Database Cleaner Configuration

```ruby
# spec/support/database_cleaner.rb
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  # For schema strategy tests
  config.around(:each, schema_strategy: true) do |example|
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.cleaning do
      example.run
    end
    DatabaseCleaner.strategy = :transaction
  end
end
```

## CI/CD Considerations

### GitHub Actions Example

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Setup database
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate

      - name: Run tests
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
        run: bundle exec rspec
```

### Parallel Tests

When running tests in parallel, ensure each process has its own tenant context:

```ruby
# spec/support/parallel_tests.rb
if ENV["TEST_ENV_NUMBER"]
  # Append process number to tenant names
  RSpec.configure do |config|
    config.before(:each) do
      @test_tenants = %w[acme globex].map do |t|
        "#{t}_#{ENV['TEST_ENV_NUMBER']}"
      end
    end
  end
end
```

## Best Practices

1. **Always reset tenant context** - Use `after(:each)` hooks to reset
2. **Use transactions** - Wrap tests in transactions for faster cleanup
3. **Isolate schema strategy tests** - Use separate test database for PostgreSQL schemas
4. **Test edge cases** - Missing tenant, invalid tenant, cross-tenant access
5. **Test callbacks** - Verify callbacks are called with correct arguments
6. **Test error handling** - Ensure errors are raised appropriately
7. **Use shared examples** - DRY up common tenant behavior tests

```ruby
RSpec.shared_examples "a tenantable model" do
  it "has tenant_id" do
    expect(described_class.column_names).to include("tenant_id")
  end

  it "is tenantable" do
    expect(described_class.tenantable?).to be true
  end

  it "scopes queries to tenant" do
    with_tenant("acme") do
      record = described_class.create!(valid_attributes)
      expect(described_class.all).to include(record)
    end
  end
end
```
