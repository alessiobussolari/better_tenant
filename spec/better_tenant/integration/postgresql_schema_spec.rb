# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PostgreSQL Schema Integration", :postgresql do
  # These tests require a real PostgreSQL database running via Docker
  # Start with: docker-compose up -d
  #
  # They verify that:
  # 1. Schemas are actually created in PostgreSQL
  # 2. Data is properly isolated between schemas
  # 3. SET search_path works correctly

  before do
    BetterTenant.reset!
    PostgreSQLHelper.cleanup_test_schemas!

    BetterTenant.configure do |config|
      config.strategy :schema
      config.tenant_names %w[acme globex initech]
      config.persistent_schemas %w[shared]
      config.schema_format "tenant_%{tenant}"
      config.require_tenant false
    end
  end

  after do
    PostgreSQLHelper.cleanup_test_schemas!
    BetterTenant.reset!
  end

  describe "schema creation" do
    it "creates tenant schema in PostgreSQL" do
      BetterTenant::Tenant.create("acme")

      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be true
    end

    it "creates schema with correct format" do
      BetterTenant::Tenant.create("globex")

      expect(PostgreSQLHelper.schema_exists?("tenant_globex")).to be true
      expect(PostgreSQLHelper.schema_exists?("globex")).to be false
    end

    it "creates multiple schemas" do
      BetterTenant::Tenant.create("acme")
      BetterTenant::Tenant.create("globex")
      BetterTenant::Tenant.create("initech")

      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be true
      expect(PostgreSQLHelper.schema_exists?("tenant_globex")).to be true
      expect(PostgreSQLHelper.schema_exists?("tenant_initech")).to be true
    end

    it "is idempotent - creating same schema twice does not error" do
      expect {
        BetterTenant::Tenant.create("acme")
        BetterTenant::Tenant.create("acme")
      }.not_to raise_error

      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be true
    end
  end

  describe "schema switching" do
    before do
      BetterTenant::Tenant.create("acme")
      BetterTenant::Tenant.create("globex")
    end

    it "switches search_path to tenant schema" do
      BetterTenant::Tenant.switch!("acme")

      search_path = PostgreSQLHelper.search_path
      expect(search_path).to include("tenant_acme")
    end

    it "includes persistent schemas in search_path" do
      BetterTenant::Tenant.switch!("acme")

      search_path = PostgreSQLHelper.search_path
      expect(search_path).to include("tenant_acme")
      expect(search_path).to include("shared")
      expect(search_path).to include("public")
    end

    it "changes current_schema() to tenant schema" do
      BetterTenant::Tenant.switch!("acme")

      current = PostgreSQLHelper.current_schema
      expect(current).to eq("tenant_acme")
    end

    it "block-based switch restores previous search_path" do
      BetterTenant::Tenant.switch!("acme")
      initial_search_path = PostgreSQLHelper.search_path

      BetterTenant::Tenant.switch("globex") do
        expect(PostgreSQLHelper.search_path).to include("tenant_globex")
      end

      expect(PostgreSQLHelper.search_path).to eq(initial_search_path)
    end

    it "reset restores default search_path" do
      BetterTenant::Tenant.switch!("acme")
      BetterTenant::Tenant.reset

      search_path = PostgreSQLHelper.search_path
      expect(search_path).not_to include("tenant_acme")
      expect(search_path).to include("public")
    end
  end

  describe "data isolation" do
    before do
      BetterTenant::Tenant.create("acme")
      BetterTenant::Tenant.create("globex")

      # Create test table in each tenant schema
      PostgreSQLHelper.create_test_table_in_schema("tenant_acme")
      PostgreSQLHelper.create_test_table_in_schema("tenant_globex")
    end

    it "inserts data into correct schema" do
      BetterTenant::Tenant.switch!("acme")

      PostgreSQLHelper.connection.execute(<<~SQL)
        INSERT INTO test_records (name) VALUES ('Acme Record 1')
      SQL

      # Count in tenant_acme schema
      acme_count = PostgreSQLHelper.table_count_in_schema("tenant_acme", "test_records")
      expect(acme_count).to eq(1)

      # Count in tenant_globex schema (should be 0)
      globex_count = PostgreSQLHelper.table_count_in_schema("tenant_globex", "test_records")
      expect(globex_count).to eq(0)
    end

    it "queries only see data from current tenant" do
      # Insert into acme
      BetterTenant::Tenant.switch("acme") do
        PostgreSQLHelper.connection.execute(<<~SQL)
          INSERT INTO test_records (name) VALUES ('Acme Record 1')
        SQL
        PostgreSQLHelper.connection.execute(<<~SQL)
          INSERT INTO test_records (name) VALUES ('Acme Record 2')
        SQL
      end

      # Insert into globex
      BetterTenant::Tenant.switch("globex") do
        PostgreSQLHelper.connection.execute(<<~SQL)
          INSERT INTO test_records (name) VALUES ('Globex Record 1')
        SQL
      end

      # Query in acme context
      BetterTenant::Tenant.switch("acme") do
        result = PostgreSQLHelper.connection.execute("SELECT COUNT(*) as count FROM test_records")
        expect(result.first["count"].to_i).to eq(2)
      end

      # Query in globex context
      BetterTenant::Tenant.switch("globex") do
        result = PostgreSQLHelper.connection.execute("SELECT COUNT(*) as count FROM test_records")
        expect(result.first["count"].to_i).to eq(1)
      end
    end

    it "prevents cross-tenant data access" do
      # Insert into acme
      BetterTenant::Tenant.switch("acme") do
        PostgreSQLHelper.connection.execute(<<~SQL)
          INSERT INTO test_records (name) VALUES ('Secret Acme Data')
        SQL
      end

      # Try to access from globex
      BetterTenant::Tenant.switch("globex") do
        result = PostgreSQLHelper.connection.execute(<<~SQL)
          SELECT * FROM test_records WHERE name = 'Secret Acme Data'
        SQL
        expect(result.count).to eq(0)
      end
    end

    it "fully qualified table name can access specific schema" do
      # Insert into acme
      BetterTenant::Tenant.switch("acme") do
        PostgreSQLHelper.connection.execute(<<~SQL)
          INSERT INTO test_records (name) VALUES ('Acme Data')
        SQL
      end

      # From globex context, access acme with fully qualified name
      BetterTenant::Tenant.switch("globex") do
        result = PostgreSQLHelper.connection.execute(<<~SQL)
          SELECT * FROM tenant_acme.test_records
        SQL
        expect(result.count).to eq(1)
        expect(result.first["name"]).to eq("Acme Data")
      end
    end
  end

  describe "schema drop" do
    before do
      BetterTenant::Tenant.create("acme")
      PostgreSQLHelper.create_test_table_in_schema("tenant_acme")

      BetterTenant::Tenant.switch("acme") do
        PostgreSQLHelper.connection.execute(<<~SQL)
          INSERT INTO test_records (name) VALUES ('Will be deleted')
        SQL
      end
    end

    it "drops schema with CASCADE" do
      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be true

      BetterTenant::Tenant.drop("acme")

      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be false
    end

    it "deletes all data in dropped schema" do
      BetterTenant::Tenant.drop("acme")

      # Schema should not exist anymore
      expect(PostgreSQLHelper.schema_exists?("tenant_acme")).to be false

      # Verify using information_schema that table doesn't exist
      result = PostgreSQLHelper.connection.execute(<<~SQL)
        SELECT COUNT(*) as count
        FROM information_schema.tables
        WHERE table_schema = 'tenant_acme' AND table_name = 'test_records'
      SQL
      expect(result.first["count"].to_i).to eq(0)
    end
  end

  describe "each_tenant iteration" do
    before do
      BetterTenant::Tenant.create("acme")
      BetterTenant::Tenant.create("globex")
      BetterTenant::Tenant.create("initech")
    end

    it "iterates through all tenants with correct schema context" do
      visited = []

      BetterTenant::Tenant.each do |tenant|
        visited << {
          tenant: tenant,
          schema: PostgreSQLHelper.current_schema
        }
      end

      expect(visited.map { |v| v[:tenant] }).to contain_exactly("acme", "globex", "initech")
      expect(visited.find { |v| v[:tenant] == "acme" }[:schema]).to eq("tenant_acme")
      expect(visited.find { |v| v[:tenant] == "globex" }[:schema]).to eq("tenant_globex")
      expect(visited.find { |v| v[:tenant] == "initech" }[:schema]).to eq("tenant_initech")
    end

    it "can insert data for each tenant during iteration" do
      BetterTenant::Tenant.each do |tenant|
        PostgreSQLHelper.create_test_table_in_schema("tenant_#{tenant}")
        PostgreSQLHelper.connection.execute(<<~SQL)
          INSERT INTO test_records (name) VALUES ('#{tenant} record')
        SQL
      end

      # Verify each tenant has exactly 1 record
      %w[acme globex initech].each do |tenant|
        count = PostgreSQLHelper.table_count_in_schema("tenant_#{tenant}", "test_records")
        expect(count).to eq(1)
      end
    end
  end

  describe "persistent schemas" do
    before do
      # Create shared schema
      PostgreSQLHelper.connection.execute("CREATE SCHEMA IF NOT EXISTS shared")
      PostgreSQLHelper.connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS shared.shared_config (
          id SERIAL PRIMARY KEY,
          key VARCHAR(255) NOT NULL,
          value TEXT
        )
      SQL
      PostgreSQLHelper.connection.execute(<<~SQL)
        INSERT INTO shared.shared_config (key, value) VALUES ('app_name', 'BetterTenant')
      SQL

      BetterTenant::Tenant.create("acme")
    end

    after do
      PostgreSQLHelper.connection.execute("DROP SCHEMA IF EXISTS shared CASCADE")
    end

    it "shared schema is accessible from tenant context" do
      BetterTenant::Tenant.switch("acme") do
        result = PostgreSQLHelper.connection.execute(<<~SQL)
          SELECT * FROM shared.shared_config WHERE key = 'app_name'
        SQL
        expect(result.first["value"]).to eq("BetterTenant")
      end
    end

    it "shared schema tables accessible without fully qualified name" do
      BetterTenant::Tenant.switch("acme") do
        # Because shared is in search_path, we can access without schema prefix
        result = PostgreSQLHelper.connection.execute(<<~SQL)
          SELECT * FROM shared_config WHERE key = 'app_name'
        SQL
        expect(result.first["value"]).to eq("BetterTenant")
      end
    end
  end

  describe "error handling" do
    it "raises error for non-existent tenant" do
      expect {
        BetterTenant::Tenant.switch!("nonexistent")
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end

    it "validates tenant before creating schema" do
      expect {
        BetterTenant::Tenant.create("nonexistent")
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end
  end

  describe "custom schema format" do
    before do
      BetterTenant.reset!
      PostgreSQLHelper.cleanup_test_schemas!("custom_")

      BetterTenant.configure do |config|
        config.strategy :schema
        config.tenant_names %w[acme]
        config.persistent_schemas %w[shared]
        config.schema_format "custom_%{tenant}_schema"
        config.require_tenant false
      end
    end

    after do
      PostgreSQLHelper.cleanup_test_schemas!("custom_")
    end

    it "creates schema with custom format" do
      BetterTenant::Tenant.create("acme")

      expect(PostgreSQLHelper.schema_exists?("custom_acme_schema")).to be true
    end

    it "switches to custom format schema" do
      BetterTenant::Tenant.create("acme")
      BetterTenant::Tenant.switch!("acme")

      current = PostgreSQLHelper.current_schema
      expect(current).to eq("custom_acme_schema")
    end
  end
end
