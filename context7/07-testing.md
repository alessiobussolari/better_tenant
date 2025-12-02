# Testing - Quick Reference

Testing multi-tenant Rails apps with BetterTenant.

---

## RSpec Setup

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:each) { BetterTenant.reset! }
  config.after(:each) { BetterTenant::Tenant.reset rescue nil }
end
```

## Helper Module

```ruby
# spec/support/better_tenant_helpers.rb
module BetterTenantHelpers
  def with_tenant(tenant, &block)
    BetterTenant::Tenant.switch(tenant, &block)
  end

  def configure_column_strategy(tenants: %w[acme globex])
    BetterTenant.configure do |config|
      config.strategy :column
      config.tenant_column :tenant_id
      config.tenant_names tenants
    end
  end
end

RSpec.configure { |c| c.include BetterTenantHelpers }
```

---

## Model Tests

```ruby
describe Article do
  before { configure_column_strategy }

  it "scopes queries to tenant" do
    with_tenant("acme") { Article.create!(title: "A") }
    with_tenant("globex") { Article.create!(title: "B") }

    with_tenant("acme") do
      expect(Article.count).to eq(1)
    end
  end

  it "sets tenant_id automatically" do
    with_tenant("acme") do
      article = Article.create!(title: "Test")
      expect(article.tenant_id).to eq("acme")
    end
  end
end
```

---

## Request Tests

```ruby
describe "Middleware", type: :request do
  before do
    BetterTenant.configure do |config|
      config.strategy :column
      config.tenant_names %w[acme]
      config.elevator :subdomain
    end
  end

  it "detects tenant from subdomain" do
    host! "acme.example.com"
    get "/articles"
    expect(response).to have_http_status(:success)
  end
end
```

---

## Job Tests

```ruby
describe ProcessOrderJob do
  before { configure_column_strategy }

  it "captures tenant" do
    with_tenant("acme") do
      job = ProcessOrderJob.new(123)
      expect(job.tenant_for_job).to eq("acme")
    end
  end

  it "serializes tenant" do
    with_tenant("acme") do
      job = ProcessOrderJob.new(123)
      expect(job.serialize["tenant_for_job"]).to eq("acme")
    end
  end
end
```

---

## Shared Examples

```ruby
RSpec.shared_examples "tenantable model" do
  it "is tenantable" do
    expect(described_class.tenantable?).to be true
  end

  it "scopes to tenant" do
    with_tenant("acme") do
      record = described_class.create!(valid_attributes)
      expect(described_class.all).to include(record)
    end
  end
end
```

---

## Database Cleaner

```ruby
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end
end
```
