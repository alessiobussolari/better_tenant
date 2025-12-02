# ActiveJob Integration

Tenant context in background jobs.

---

## Setup

```ruby
class ApplicationJob < ActiveJob::Base
  include BetterTenant::ActiveJobExtension
end
```

--------------------------------

## Usage

```ruby
class ProcessJob < ApplicationJob
  include BetterTenant::ActiveJobExtension

  def perform(id)
    # Tenant auto-restored
    Model.find(id)
  end
end

# Enqueue in tenant context
BetterTenant::Tenant.switch("acme") do
  ProcessJob.perform_later(123)
  # Runs in "acme" context
end
```

--------------------------------

## How It Works

```
1. Job created -> captures tenant
2. Serialized -> includes tenant_for_job
3. Deserialized -> restores tenant
4. Perform -> executes in context
```

--------------------------------

## Cross-Tenant Jobs

```ruby
class AllTenantsJob < ApplicationJob
  # Don't include extension

  def perform
    BetterTenant::Tenant.each do |tenant|
      TenantJob.perform_later(tenant)
    end
  end
end
```

--------------------------------

## Manual Context

```ruby
class ManualJob < ApplicationJob
  def perform(tenant_name)
    BetterTenant::Tenant.switch(tenant_name) do
      # Process
    end
  end
end
```

--------------------------------
