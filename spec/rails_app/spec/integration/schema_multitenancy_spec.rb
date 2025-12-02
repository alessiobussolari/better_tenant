# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Schema Multitenancy End-to-End", :postgresql do
  # End-to-end tests using the rails_app models with real PostgreSQL
  # These tests verify the complete flow of:
  # 1. Creating tenant schemas
  # 2. Running migrations per tenant
  # 3. Using ActiveRecord models with tenant isolation
  # 4. Middleware integration

  before do
    BetterTenant.reset!
    PostgreSQLHelper.cleanup_test_schemas!

    BetterTenant.configure do |config|
      config.strategy :schema
      config.tenant_names %w[acme globex]
      config.persistent_schemas %w[shared]
      config.schema_format "tenant_%{tenant}"
      config.require_tenant false
    end

    # Create tenant schemas with articles table
    %w[acme globex].each do |tenant|
      BetterTenant::Tenant.create(tenant)
      create_articles_table_in_schema("tenant_#{tenant}")
    end
  end

  after do
    PostgreSQLHelper.cleanup_test_schemas!
    BetterTenant.reset!
  end

  def create_articles_table_in_schema(schema_name)
    PostgreSQLHelper.connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS #{schema_name}.articles (
        id SERIAL PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        content TEXT,
        tenant_id VARCHAR(255),
        status VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end

  describe "ActiveRecord model operations" do
    # Create a test model class that uses the PostgreSQL connection
    let(:article_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"

        def self.name
          "Article"
        end
      end
    end

    it "creates records in correct tenant schema" do
      BetterTenant::Tenant.switch("acme") do
        article_class.create!(title: "Acme Article", content: "Content for Acme")
      end

      BetterTenant::Tenant.switch("globex") do
        article_class.create!(title: "Globex Article", content: "Content for Globex")
      end

      # Verify isolation
      acme_count = PostgreSQLHelper.table_count_in_schema("tenant_acme", "articles")
      globex_count = PostgreSQLHelper.table_count_in_schema("tenant_globex", "articles")

      expect(acme_count).to eq(1)
      expect(globex_count).to eq(1)
    end

    it "queries only return records from current tenant" do
      # Create 3 records in acme, 2 in globex
      BetterTenant::Tenant.switch("acme") do
        3.times { |i| article_class.create!(title: "Acme #{i}") }
      end

      BetterTenant::Tenant.switch("globex") do
        2.times { |i| article_class.create!(title: "Globex #{i}") }
      end

      # Query counts
      BetterTenant::Tenant.switch("acme") do
        expect(article_class.count).to eq(3)
      end

      BetterTenant::Tenant.switch("globex") do
        expect(article_class.count).to eq(2)
      end
    end

    it "find returns record only from current tenant" do
      acme_article_id = nil
      globex_article_id = nil

      BetterTenant::Tenant.switch("acme") do
        article = article_class.create!(title: "Secret Acme Data")
        acme_article_id = article.id
      end

      BetterTenant::Tenant.switch("globex") do
        article = article_class.create!(title: "Globex Data")
        globex_article_id = article.id
      end

      # Acme can find its article
      BetterTenant::Tenant.switch("acme") do
        expect(article_class.find(acme_article_id).title).to eq("Secret Acme Data")
      end

      # Globex can find its article
      BetterTenant::Tenant.switch("globex") do
        expect(article_class.find(globex_article_id).title).to eq("Globex Data")
      end

      # Note: With schema strategy, IDs might collide since each schema has its own sequence
      # This is expected behavior
    end

    it "update_all affects only current tenant" do
      BetterTenant::Tenant.switch("acme") do
        article_class.create!(title: "Acme 1", status: "draft")
        article_class.create!(title: "Acme 2", status: "draft")
      end

      BetterTenant::Tenant.switch("globex") do
        article_class.create!(title: "Globex 1", status: "draft")
      end

      # Update all in acme
      BetterTenant::Tenant.switch("acme") do
        article_class.update_all(status: "published")
      end

      # Verify acme updated
      BetterTenant::Tenant.switch("acme") do
        expect(article_class.where(status: "published").count).to eq(2)
      end

      # Verify globex unchanged
      BetterTenant::Tenant.switch("globex") do
        expect(article_class.where(status: "draft").count).to eq(1)
        expect(article_class.where(status: "published").count).to eq(0)
      end
    end

    it "delete_all affects only current tenant" do
      BetterTenant::Tenant.switch("acme") do
        article_class.create!(title: "Acme Article")
      end

      BetterTenant::Tenant.switch("globex") do
        article_class.create!(title: "Globex Article")
      end

      # Delete all in acme
      BetterTenant::Tenant.switch("acme") do
        article_class.delete_all
      end

      # Verify acme empty
      BetterTenant::Tenant.switch("acme") do
        expect(article_class.count).to eq(0)
      end

      # Verify globex unchanged
      BetterTenant::Tenant.switch("globex") do
        expect(article_class.count).to eq(1)
      end
    end
  end

  describe "tenant iteration with data" do
    let(:article_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"

        def self.name
          "Article"
        end
      end
    end

    before do
      BetterTenant::Tenant.switch("acme") do
        2.times { |i| article_class.create!(title: "Acme #{i}") }
      end

      BetterTenant::Tenant.switch("globex") do
        3.times { |i| article_class.create!(title: "Globex #{i}") }
      end
    end

    it "each_tenant iterates with correct data context" do
      counts = {}

      BetterTenant::Tenant.each do |tenant|
        counts[tenant] = article_class.count
      end

      expect(counts["acme"]).to eq(2)
      expect(counts["globex"]).to eq(3)
    end

    it "can process data for all tenants" do
      # Update status for all articles in all tenants
      BetterTenant::Tenant.each do |tenant|
        article_class.update_all(status: "processed_#{tenant}")
      end

      # Verify each tenant has correct status
      BetterTenant::Tenant.switch("acme") do
        expect(article_class.first.status).to eq("processed_acme")
      end

      BetterTenant::Tenant.switch("globex") do
        expect(article_class.first.status).to eq("processed_globex")
      end
    end
  end

  describe "middleware integration" do
    let(:article_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"

        def self.name
          "Article"
        end
      end
    end

    it "middleware sets correct tenant context from subdomain" do
      tenant_during_request = nil
      article_count = nil

      # Seed some data
      BetterTenant::Tenant.switch("acme") do
        article_class.create!(title: "Acme Article")
      end

      test_app = lambda do |_env|
        tenant_during_request = BetterTenant::Tenant.current
        article_count = article_class.count
        [200, {}, ["OK"]]
      end

      middleware = BetterTenant::Middleware.new(test_app, :subdomain)
      env = Rack::MockRequest.env_for("http://acme.example.com/articles")

      middleware.call(env)

      expect(tenant_during_request).to eq("acme")
      expect(article_count).to eq(1)
    end

    it "middleware sets correct tenant context from header" do
      tenant_during_request = nil
      article_count = nil

      # Seed some data in globex
      BetterTenant::Tenant.switch("globex") do
        2.times { article_class.create!(title: "Globex Article") }
      end

      test_app = lambda do |_env|
        tenant_during_request = BetterTenant::Tenant.current
        article_count = article_class.count
        [200, {}, ["OK"]]
      end

      middleware = BetterTenant::Middleware.new(test_app, :header)
      env = Rack::MockRequest.env_for("http://example.com/articles", "HTTP_X_TENANT" => "globex")

      middleware.call(env)

      expect(tenant_during_request).to eq("globex")
      expect(article_count).to eq(2)
    end

    it "middleware resets tenant after request" do
      test_app = ->(_env) { [200, {}, ["OK"]] }
      middleware = BetterTenant::Middleware.new(test_app, :subdomain)
      env = Rack::MockRequest.env_for("http://acme.example.com/articles")

      middleware.call(env)

      expect(BetterTenant::Tenant.current).to be_nil
    end

    it "middleware handles request errors without leaking tenant context" do
      test_app = ->(_env) { raise "Request Error" }
      middleware = BetterTenant::Middleware.new(test_app, :subdomain)
      env = Rack::MockRequest.env_for("http://acme.example.com/articles")

      expect { middleware.call(env) }.to raise_error("Request Error")
      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "concurrent request simulation" do
    let(:article_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"

        def self.name
          "Article"
        end
      end
    end

    it "sequential requests have correct tenant isolation" do
      results = []

      # Request 1: Create article in acme
      BetterTenant::Tenant.switch("acme") do
        article_class.create!(title: "Acme Article")
        results << { tenant: "acme", count: article_class.count }
      end

      # Request 2: Create article in globex
      BetterTenant::Tenant.switch("globex") do
        article_class.create!(title: "Globex Article")
        results << { tenant: "globex", count: article_class.count }
      end

      # Request 3: Read from acme (should still be 1)
      BetterTenant::Tenant.switch("acme") do
        results << { tenant: "acme", count: article_class.count }
      end

      expect(results[0]).to eq({ tenant: "acme", count: 1 })
      expect(results[1]).to eq({ tenant: "globex", count: 1 })
      expect(results[2]).to eq({ tenant: "acme", count: 1 })
    end
  end

  describe "schema existence verification" do
    it "tenant_exists? returns true only for created schemas" do
      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be true
      expect(PostgreSQLHelper.schema_exists?("tenant_globex")).to be true
      expect(PostgreSQLHelper.schema_exists?("tenant_nonexistent")).to be false
    end

    it "dropping tenant removes schema completely" do
      BetterTenant::Tenant.drop("acme")

      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be false
    end
  end
end
