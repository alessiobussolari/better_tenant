# Getting Started

Installation and basic setup for BetterTenant.

---

## Installation

### Gemfile

```ruby
gem 'better_tenant'
```

--------------------------------

### Bundle Install

```bash
bundle install
```

--------------------------------

### Generate Initializer

```bash
rails generate better_tenant:install
```

Creates: `config/initializers/better_tenant.rb`

--------------------------------

## CLI Commands Reference

### Installation

```bash
bundle add better_tenant
```

--------------------------------

### Install Generator

```bash
rails generate better_tenant:install
rails generate better_tenant:install --strategy=schema
rails generate better_tenant:install --strategy=column --migration --table=articles
```

--------------------------------

### Rake Tasks

```bash
rake better_tenant:list
rake better_tenant:config
rake better_tenant:create[tenant_name]
rake better_tenant:drop[tenant_name]
rake better_tenant:migrate
```

--------------------------------

## Column Strategy Setup

```ruby
BetterTenant.configure do |config|
  config.strategy :column
  config.tenant_column :tenant_id
  config.tenant_names %w[acme globex]
end

class Article < ApplicationRecord
  include BetterTenant::ActiveRecordExtension
end
```

--------------------------------

## Schema Strategy Setup

```ruby
BetterTenant.configure do |config|
  config.strategy :schema
  config.tenant_names -> { Organization.pluck(:name) }
  config.excluded_models %w[User Organization]
end
```

--------------------------------

## Requirements

- Ruby >= 3.2.0
- Rails >= 8.1.0
- PostgreSQL (schema strategy)

--------------------------------
