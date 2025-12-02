# frozen_string_literal: true

# Helper module for PostgreSQL integration tests
# These tests require Docker PostgreSQL running: docker-compose up -d
module PostgreSQLHelper
  POSTGRESQL_CONFIG = {
    adapter: "postgresql",
    host: ENV.fetch("POSTGRES_HOST", "localhost"),
    port: ENV.fetch("POSTGRES_PORT", 5433).to_i,
    database: "better_tenant_test",
    username: "better_tenant_test",
    password: "test_password"
  }.freeze

  SQLITE_CONFIG = {
    adapter: "sqlite3",
    database: File.expand_path("../rails_app/storage/test.sqlite3", __dir__)
  }.freeze

  class << self
    def available?
      return @available if defined?(@available)

      @available = check_availability
    end

    def connection
      @connection ||= establish_connection
    end

    def establish_connection
      ActiveRecord::Base.establish_connection(POSTGRESQL_CONFIG)
      ActiveRecord::Base.connection
    end

    def restore_sqlite_connection!
      @connection = nil
      ActiveRecord::Base.establish_connection(SQLITE_CONFIG)
    end

    def reset_connection!
      @connection = nil
      @available = nil
    end

    def create_test_table_in_schema(schema_name, table_name = "test_records")
      connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{schema_name}.#{table_name} (
          id SERIAL PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      SQL
    end

    def schema_exists?(schema_name)
      result = connection.execute(<<~SQL)
        SELECT 1 FROM pg_namespace WHERE nspname = '#{schema_name}'
      SQL
      result.any?
    end

    def current_schema
      result = connection.execute("SELECT current_schema()")
      result.first["current_schema"]
    end

    def search_path
      result = connection.execute("SHOW search_path")
      result.first["search_path"]
    end

    def table_count_in_schema(schema_name, table_name)
      result = connection.execute(<<~SQL)
        SELECT COUNT(*) as count FROM #{schema_name}.#{table_name}
      SQL
      result.first["count"].to_i
    end

    def cleanup_test_schemas!(prefix = "tenant_")
      schemas = connection.execute(<<~SQL)
        SELECT nspname FROM pg_namespace
        WHERE nspname LIKE '#{prefix}%'
      SQL

      schemas.each do |row|
        connection.execute("DROP SCHEMA IF EXISTS #{row['nspname']} CASCADE")
      end
    end

    private

    def check_availability
      test_connection = PG.connect(
        host: POSTGRESQL_CONFIG[:host],
        port: POSTGRESQL_CONFIG[:port],
        dbname: POSTGRESQL_CONFIG[:database],
        user: POSTGRESQL_CONFIG[:username],
        password: POSTGRESQL_CONFIG[:password],
        connect_timeout: 5
      )
      test_connection.close
      true
    rescue PG::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT
      false
    end
  end
end

RSpec.configure do |config|
  config.before(:each, :postgresql) do
    unless PostgreSQLHelper.available?
      skip "PostgreSQL non disponibile. Avvia con: docker-compose up -d"
    end
    # Ensure PostgreSQL connection is established
    PostgreSQLHelper.establish_connection
  end

  config.after(:each, :postgresql) do
    if PostgreSQLHelper.available?
      PostgreSQLHelper.cleanup_test_schemas!
      BetterTenant.reset! if defined?(BetterTenant)
      # Restore SQLite connection for other tests
      PostgreSQLHelper.restore_sqlite_connection!
    end
  end
end
