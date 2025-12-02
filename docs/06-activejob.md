# ActiveJob Integration

Automatic tenant context preservation in background jobs.

---

## Overview

BetterTenant provides an ActiveJob extension that automatically captures and restores tenant context when jobs are enqueued and performed. This ensures background jobs execute in the correct tenant context.

## Setup

Include the extension in your job classes:

```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  include BetterTenant::ActiveJobExtension
end
```

Or per-job:

```ruby
# app/jobs/process_order_job.rb
class ProcessOrderJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(order_id)
    order = Order.find(order_id)
    order.process!
  end
end
```

## How It Works

1. **Job Creation**: When job is created, current tenant is captured
2. **Serialization**: Tenant is serialized with job data
3. **Deserialization**: Tenant is restored when job is loaded
4. **Execution**: Job performs within tenant context
5. **Cleanup**: Tenant context is reset after job completes

```
┌─────────────────────────────────────────────────────────────┐
│  Web Request (tenant: "acme")                               │
│                                                              │
│  ProcessOrderJob.perform_later(order.id)                    │
│        │                                                     │
│        ▼                                                     │
│  ┌─────────────────────────────────────────┐                │
│  │ Job Created                             │                │
│  │ tenant_for_job = "acme"                 │                │
│  └─────────────────────────────────────────┘                │
│        │                                                     │
│        ▼                                                     │
│  ┌─────────────────────────────────────────┐                │
│  │ Serialized to Queue                     │                │
│  │ { "tenant_for_job": "acme", ... }       │                │
│  └─────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Background Worker                                          │
│                                                              │
│  ┌─────────────────────────────────────────┐                │
│  │ Deserialized from Queue                 │                │
│  │ tenant_for_job = "acme"                 │                │
│  └─────────────────────────────────────────┘                │
│        │                                                     │
│        ▼                                                     │
│  ┌─────────────────────────────────────────┐                │
│  │ BetterTenant::Tenant.switch("acme")     │                │
│  │                                         │                │
│  │   order = Order.find(order_id)          │                │
│  │   # WHERE tenant_id = 'acme'            │                │
│  │   order.process!                        │                │
│  │                                         │                │
│  └─────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Usage

### Basic Example

```ruby
class ProcessOrderJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(order_id)
    # Tenant context is automatically restored
    order = Order.find(order_id)  # Scoped to original tenant
    order.process!
    OrderMailer.confirmation(order).deliver_now
  end
end

# Enqueue in tenant context
BetterTenant::Tenant.switch("acme") do
  order = Order.create!(items: [...])
  ProcessOrderJob.perform_later(order.id)
  # Job will execute in "acme" context
end
```

### With Arguments

```ruby
class ReportGeneratorJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(report_type, date_range)
    # All queries scoped to tenant
    data = case report_type
    when "sales"
      Order.where(created_at: date_range).sum(:total)
    when "users"
      User.where(created_at: date_range).count
    end

    Report.create!(type: report_type, data: data)
  end
end

# Enqueue
BetterTenant::Tenant.switch("acme") do
  ReportGeneratorJob.perform_later("sales", 1.month.ago..Time.current)
end
```

### Scheduled Jobs

```ruby
class DailyDigestJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform
    # Runs in captured tenant context
    users = User.where(digest_enabled: true)
    users.each do |user|
      DigestMailer.daily(user).deliver_later
    end
  end
end

# Schedule for each tenant
BetterTenant::Tenant.each do |tenant|
  BetterTenant::Tenant.switch(tenant) do
    DailyDigestJob.set(wait_until: Date.tomorrow.beginning_of_day).perform_later
  end
end
```

## Cross-Tenant Jobs

### Processing All Tenants

```ruby
class GlobalMaintenanceJob < ApplicationJob
  # Don't include ActiveJobExtension for cross-tenant jobs

  def perform
    BetterTenant::Tenant.each do |tenant|
      BetterTenant::Tenant.switch(tenant) do
        cleanup_old_records
      end
    end
  end

  private

  def cleanup_old_records
    Article.where("created_at < ?", 1.year.ago).destroy_all
  end
end
```

### Spawning Tenant Jobs

```ruby
class BatchProcessJob < ApplicationJob
  # No extension needed

  def perform
    # Create a job for each tenant
    BetterTenant::Tenant.tenant_names.each do |tenant|
      TenantProcessJob.perform_later(tenant)
    end
  end
end

class TenantProcessJob < ApplicationJob
  # No extension - manually switch

  def perform(tenant_name)
    BetterTenant::Tenant.switch(tenant_name) do
      process_tenant_data
    end
  end
end
```

## Error Handling

### Tenant Not Found

```ruby
class SafeJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  rescue_from BetterTenant::Errors::TenantNotFoundError do |exception|
    Rails.logger.error "Tenant not found: #{exception.message}"
    # Job will not retry
  end

  def perform(item_id)
    Item.find(item_id).process!
  end
end
```

### Retry with Tenant

```ruby
class RetryableJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  def perform(order_id)
    Order.find(order_id).fulfill!
  end
end

# Tenant context is preserved across retries
```

## Testing

### Unit Tests

```ruby
# spec/jobs/process_order_job_spec.rb
describe ProcessOrderJob do
  before do
    BetterTenant.configure do |c|
      c.strategy :column
      c.tenant_names %w[acme]
    end
  end

  it "processes order in tenant context" do
    order = nil

    BetterTenant::Tenant.switch("acme") do
      order = Order.create!(status: "pending")
      ProcessOrderJob.perform_now(order.id)
    end

    expect(order.reload.status).to eq("processed")
  end
end
```

### Serialization Tests

```ruby
describe ProcessOrderJob do
  it "serializes tenant context" do
    job = nil

    BetterTenant::Tenant.switch("acme") do
      job = ProcessOrderJob.new(123)
    end

    serialized = job.serialize
    expect(serialized["tenant_for_job"]).to eq("acme")
  end

  it "deserializes tenant context" do
    job_data = {
      "job_class" => "ProcessOrderJob",
      "arguments" => [123],
      "tenant_for_job" => "acme"
    }

    job = ProcessOrderJob.deserialize(job_data)
    expect(job.tenant_for_job).to eq("acme")
  end
end
```

### Integration Tests

```ruby
describe "Background job tenant isolation" do
  include ActiveJob::TestHelper

  before do
    BetterTenant.configure do |c|
      c.strategy :column
      c.tenant_names %w[acme globex]
    end
  end

  it "maintains tenant isolation across job execution" do
    acme_order = globex_order = nil

    BetterTenant::Tenant.switch("acme") do
      acme_order = Order.create!(name: "Acme Order")
      ProcessOrderJob.perform_later(acme_order.id)
    end

    BetterTenant::Tenant.switch("globex") do
      globex_order = Order.create!(name: "Globex Order")
      ProcessOrderJob.perform_later(globex_order.id)
    end

    perform_enqueued_jobs

    expect(acme_order.reload.processed?).to be true
    expect(globex_order.reload.processed?).to be true
  end
end
```

## Queue Adapters

### Sidekiq

```ruby
# config/initializers/sidekiq.rb
# Tenant is serialized in job arguments automatically
```

### Delayed Job

```ruby
# Works out of the box with serialization
```

### Solid Queue (Rails 8+)

```ruby
# Native Rails queue, works automatically
```

## Best Practices

### Always Use Extension for Tenant Jobs

```ruby
# Good
class TenantJob < ApplicationJob
  include BetterTenant::ActiveJobExtension
end

# Bad - will run without tenant context
class TenantJob < ApplicationJob
  def perform
    # No tenant context!
  end
end
```

### Use perform_later for Tenant Jobs

```ruby
# Good - captures tenant context
BetterTenant::Tenant.switch("acme") do
  MyJob.perform_later(args)
end

# Careful - perform_now might not capture correctly in all contexts
MyJob.perform_now(args)
```

### Clear Tenant for Admin Jobs

```ruby
class AdminReportJob < ApplicationJob
  # Don't include extension for cross-tenant admin jobs

  def perform
    # Process all tenants
  end
end
```
