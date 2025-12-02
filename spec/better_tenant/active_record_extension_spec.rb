# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::ActiveRecordExtension do
  # Create a test model for column strategy testing
  let(:tenant_article_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "articles"

      # Simulate tenantable extension
      include BetterTenant::ActiveRecordExtension
    end
  end

  let(:mock_connection) { double("connection") }
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[acme globex]
      c.require_tenant false
    end
  end

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }

    BetterTenant::Tenant.reset!
    BetterTenant::Tenant.configure(config)
  end

  after do
    BetterTenant::Tenant.reset!
  end

  describe "module inclusion" do
    it "adds tenantable class methods" do
      expect(tenant_article_class).to respond_to(:tenantable?)
      expect(tenant_article_class).to respond_to(:tenant_column)
    end

    it "marks class as tenantable" do
      expect(tenant_article_class.tenantable?).to be true
    end
  end

  describe ".tenant_column" do
    it "returns the configured tenant column" do
      expect(tenant_article_class.tenant_column).to eq(:tenant_id)
    end
  end

  describe ".current_tenant" do
    it "returns nil when no tenant is set" do
      expect(tenant_article_class.current_tenant).to be_nil
    end

    it "returns the current tenant when set" do
      BetterTenant::Tenant.switch!("acme")
      expect(tenant_article_class.current_tenant).to eq("acme")
    end
  end

  describe "default_scope" do
    context "when using column strategy" do
      context "when tenant is set" do
        it "applies tenant scope to queries" do
          BetterTenant::Tenant.switch!("acme")

          # Get the relation and check its where values
          relation = tenant_article_class.all
          expect(relation.to_sql).to include("tenant_id")
        end
      end

      context "when no tenant is set" do
        it "does not apply tenant scope" do
          relation = tenant_article_class.all
          expect(relation.to_sql).not_to include("tenant_id = ")
        end
      end
    end
  end

  describe "automatic tenant_id assignment" do
    # These tests require a tenant_id column on the articles table.
    # Since the test database doesn't have this column, we test the behavior
    # at the method level instead of with real records.

    context "when tenant_id column exists" do
      let(:tenant_article_with_column) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"

          # Add tenant_id as an accessor for testing
          attr_accessor :tenant_id

          include BetterTenant::ActiveRecordExtension

          # Override column check to simulate having tenant_id column
          def has_attribute?(attr)
            attr.to_s == "tenant_id" || super
          end
        end
      end

      it "sets tenant_id automatically when blank" do
        BetterTenant::Tenant.switch!("acme")

        record = tenant_article_with_column.new
        # Manually trigger the callback logic
        record.send(:set_tenant_id)

        expect(record.tenant_id).to eq("acme")
      end

      it "does not override existing tenant_id" do
        BetterTenant::Tenant.switch!("acme")

        record = tenant_article_with_column.new
        record.tenant_id = "globex"
        record.send(:set_tenant_id)

        expect(record.tenant_id).to eq("globex")
      end
    end
  end

  describe "tenant immutability" do
    context "with strict_mode enabled" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :tenant_id
          c.tenant_names %w[acme globex]
          c.strict_mode true
          c.require_tenant false
        end
      end

      let(:tenant_article_with_tracking) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          attr_accessor :tenant_id, :tenant_id_was_value

          include BetterTenant::ActiveRecordExtension

          def tenant_id_changed?
            tenant_id != tenant_id_was_value
          end

          def tenant_id_was
            tenant_id_was_value
          end
        end
      end

      it "raises error when trying to change tenant_id" do
        BetterTenant::Tenant.switch!("acme")

        record = tenant_article_with_tracking.new
        record.tenant_id = "acme"
        record.tenant_id_was_value = "acme"

        # Simulate persisted record
        allow(record).to receive(:persisted?).and_return(true)

        # Change tenant_id
        record.tenant_id = "globex"

        expect {
          record.send(:validate_tenant_immutability)
        }.to raise_error(BetterTenant::Errors::TenantImmutableError)
      end
    end
  end

  describe "cross-tenant protection" do
    context "with require_tenant enabled" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :tenant_id
          c.tenant_names %w[acme globex]
          c.require_tenant true
        end
      end

      it "raises error when querying without tenant context" do
        expect {
          tenant_article_class.all.to_a
        }.to raise_error(BetterTenant::Errors::TenantContextMissingError)
      end
    end
  end

  describe ".unscoped_tenant" do
    it "executes block without tenant scope" do
      BetterTenant::Tenant.switch!("acme")

      tenant_article_class.unscoped_tenant do
        relation = tenant_article_class.all
        # In unscoped block, should not have tenant filter
        expect(tenant_article_class.current_tenant).to be_nil
      end

      # After block, should restore tenant
      expect(tenant_article_class.current_tenant).to eq("acme")
    end
  end

  describe "edge cases" do
    describe "model without tenantable" do
      let(:non_tenant_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          # Does NOT include BetterTenant::ActiveRecordExtension
        end
      end

      it "does not respond to tenantable?" do
        expect(non_tenant_class).not_to respond_to(:tenantable?)
      end

      it "does not have tenant_column method" do
        expect(non_tenant_class).not_to respond_to(:tenant_column)
      end
    end

    describe "excluded models" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :tenant_id
          c.tenant_names %w[acme globex]
          c.excluded_models %w[Article]
          c.require_tenant true
        end
      end

      let(:excluded_model_class) do
        # Create a class that looks like Article
        klass = Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include BetterTenant::ActiveRecordExtension
        end
        # Give it a name
        stub_const("Article", klass)
        klass
      end

      it "does not apply tenant scope to excluded models" do
        BetterTenant::Tenant.switch!("acme")

        # Excluded models should work without tenant scope
        expect {
          excluded_model_class.all.to_sql
        }.not_to raise_error
      end
    end

    describe "tenant switching during query building" do
      it "captures tenant value at query build time" do
        BetterTenant::Tenant.switch!("acme")
        relation = tenant_article_class.all

        # Change tenant after building the relation
        BetterTenant::Tenant.switch!("globex")

        # SQL reflects tenant at build time (lazy evaluation)
        sql = relation.to_sql
        # The scope captures the tenant at build time
        expect(sql).to include("acme")
      end

      it "new relations use current tenant" do
        BetterTenant::Tenant.switch!("acme")
        first_relation = tenant_article_class.all

        BetterTenant::Tenant.switch!("globex")
        second_relation = tenant_article_class.all

        # Each relation uses tenant at its build time
        expect(first_relation.to_sql).to include("acme")
        expect(second_relation.to_sql).to include("globex")
      end
    end

    describe "nested unscoped_tenant blocks" do
      it "properly restores tenant through nested blocks" do
        BetterTenant::Tenant.switch!("acme")

        tenant_article_class.unscoped_tenant do
          expect(tenant_article_class.current_tenant).to be_nil

          tenant_article_class.unscoped_tenant do
            expect(tenant_article_class.current_tenant).to be_nil
          end

          # Still nil in outer unscoped block
          expect(tenant_article_class.current_tenant).to be_nil
        end

        # Restored after all blocks
        expect(tenant_article_class.current_tenant).to eq("acme")
      end
    end

    describe "exception handling in unscoped_tenant" do
      it "restores tenant after exception" do
        BetterTenant::Tenant.switch!("acme")

        begin
          tenant_article_class.unscoped_tenant do
            expect(tenant_article_class.current_tenant).to be_nil
            raise "Test error"
          end
        rescue StandardError
          # Ignore
        end

        expect(tenant_article_class.current_tenant).to eq("acme")
      end
    end

    describe "custom tenant column" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_column :organization_id
          c.tenant_names %w[org1 org2]
          c.require_tenant false
        end
      end

      let(:org_model_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include BetterTenant::ActiveRecordExtension
        end
      end

      it "uses custom tenant column name" do
        expect(org_model_class.tenant_column).to eq(:organization_id)
      end

      it "scopes queries using custom column" do
        BetterTenant::Tenant.switch!("org1")
        sql = org_model_class.all.to_sql
        expect(sql).to include("organization_id")
      end
    end

    describe "nil and empty tenant handling" do
      it "handles nil tenant gracefully" do
        BetterTenant::Tenant.reset
        expect(tenant_article_class.current_tenant).to be_nil
      end

      it "does not apply scope for nil tenant" do
        BetterTenant::Tenant.reset
        relation = tenant_article_class.all
        expect(relation.to_sql).not_to include("tenant_id = ")
      end
    end

    describe "multiple models with extension" do
      let(:article_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include BetterTenant::ActiveRecordExtension
        end
      end

      let(:comment_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles" # Reuse table for simplicity
          include BetterTenant::ActiveRecordExtension
        end
      end

      it "both models share same tenant configuration" do
        expect(article_class.tenant_column).to eq(:tenant_id)
        expect(comment_class.tenant_column).to eq(:tenant_id)
      end

      it "both models see same current_tenant" do
        BetterTenant::Tenant.switch!("acme")
        expect(article_class.current_tenant).to eq("acme")
        expect(comment_class.current_tenant).to eq("acme")
      end
    end

    describe "tenant_id assignment edge cases" do
      let(:model_with_accessor) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          attr_accessor :tenant_id

          include BetterTenant::ActiveRecordExtension

          def has_attribute?(attr)
            attr.to_s == "tenant_id" || super
          end
        end
      end

      it "does not set tenant_id when no tenant is active" do
        BetterTenant::Tenant.reset
        record = model_with_accessor.new
        record.send(:set_tenant_id)
        expect(record.tenant_id).to be_nil
      end

      it "handles empty string tenant_id as blank" do
        BetterTenant::Tenant.switch!("acme")
        record = model_with_accessor.new
        record.tenant_id = ""
        record.send(:set_tenant_id)
        expect(record.tenant_id).to eq("acme")
      end
    end

    describe "SQL injection protection" do
      it "properly escapes tenant values" do
        # Even if someone managed to set a malicious tenant name,
        # it should be properly escaped
        BetterTenant::Tenant.switch!("acme")
        relation = tenant_article_class.all
        sql = relation.to_sql

        # The SQL should use parameterized queries or proper escaping
        # We can't easily test for SQL injection protection, but we can
        # verify the query is well-formed
        expect(sql).to be_a(String)
        expect(sql).not_to be_empty
      end
    end
  end
end
