# frozen_string_literal: true

require "spec_helper"

# Configure Rails Environment
ENV["RAILS_ENV"] ||= "test"

require_relative "rails_app/config/environment"

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot_rails"
require "shoulda/matchers"
require "database_cleaner/active_record"

# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
spec_root = __dir__
Dir[File.join(spec_root, "support/**/*.rb")].sort.each { |f| require f }

# Set up migrations path
ActiveRecord::Migrator.migrations_paths = [File.expand_path("rails_app/db/migrate", __dir__)]

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [File.expand_path("fixtures", __dir__)]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Infer an example group's spec type from the file location
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces
  config.filter_rails_from_backtrace!

  # DatabaseCleaner configuration
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  # Configure BetterTenant before each request spec
  # (middleware is enabled in application.rb)
  config.before(:each, type: :request) do
    tenant_config = BetterTenant::Configurator.new.tap do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[acme globex initech]
      c.require_tenant false
    end
    BetterTenant::Tenant.configure(tenant_config)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
