# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant thread safety" do
  let(:mock_connection) { double("connection") }

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }

    BetterTenant.configure do |config|
      config.strategy :column
      config.tenant_column :tenant_id
      config.tenant_names %w[acme globex initech]
      config.require_tenant false
    end
  end

  after do
    BetterTenant::Tenant.reset!
  end

  describe "global tenant state" do
    # Note: BetterTenant uses a single global adapter instance, so tenant state
    # is shared across threads. This is similar to Apartment gem's behavior
    # and is typically used with request-scoped middleware that sets and resets
    # the tenant for each request.

    it "tenant state is shared across threads (not thread-local)" do
      BetterTenant::Tenant.switch!("acme")
      child_tenant = nil

      thread = Thread.new do
        child_tenant = BetterTenant::Tenant.current
      end
      thread.join

      # Child thread sees the parent's tenant (global state)
      expect(child_tenant).to eq("acme")
    end

    it "switch! affects global state visible to all threads" do
      BetterTenant::Tenant.switch!("acme")

      result = nil
      thread = Thread.new do
        result = BetterTenant::Tenant.current
        BetterTenant::Tenant.switch!("globex")
      end
      thread.join

      # Child thread saw "acme" and changed it to "globex"
      expect(result).to eq("acme")
      expect(BetterTenant::Tenant.current).to eq("globex")
    end
  end

  describe "block-based switching" do
    it "properly restores tenant after block completes" do
      BetterTenant::Tenant.switch!("acme")

      BetterTenant::Tenant.switch("globex") do
        expect(BetterTenant::Tenant.current).to eq("globex")
      end

      expect(BetterTenant::Tenant.current).to eq("acme")
    end

    it "properly restores tenant after exception" do
      BetterTenant::Tenant.switch!("acme")

      begin
        BetterTenant::Tenant.switch("globex") do
          raise "Test error"
        end
      rescue StandardError
        # Ignore the error
      end

      expect(BetterTenant::Tenant.current).to eq("acme")
    end

    it "properly restores nil tenant after block" do
      expect(BetterTenant::Tenant.current).to be_nil

      BetterTenant::Tenant.switch("acme") do
        expect(BetterTenant::Tenant.current).to eq("acme")
      end

      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "nested switching" do
    it "supports nested tenant switching" do
      results = []

      BetterTenant::Tenant.switch("acme") do
        results << BetterTenant::Tenant.current
        BetterTenant::Tenant.switch("globex") do
          results << BetterTenant::Tenant.current
          BetterTenant::Tenant.switch("initech") do
            results << BetterTenant::Tenant.current
          end
          results << BetterTenant::Tenant.current
        end
        results << BetterTenant::Tenant.current
      end
      results << BetterTenant::Tenant.current

      expect(results).to eq(["acme", "globex", "initech", "globex", "acme", nil])
    end

    it "restores correct tenant after nested exception" do
      BetterTenant::Tenant.switch("acme") do
        begin
          BetterTenant::Tenant.switch("globex") do
            BetterTenant::Tenant.switch("initech") do
              raise "Deep error"
            end
          end
        rescue StandardError
          # Ignore
        end

        # Should be back to acme after unwinding
        expect(BetterTenant::Tenant.current).to eq("acme")
      end
    end
  end

  describe "sequential request simulation" do
    it "properly isolates sequential requests (middleware pattern)" do
      results = []

      # Simulate request 1
      BetterTenant::Tenant.switch("acme") do
        results << BetterTenant::Tenant.current
      end

      # Simulate request 2
      BetterTenant::Tenant.switch("globex") do
        results << BetterTenant::Tenant.current
      end

      # Simulate request 3
      BetterTenant::Tenant.switch("initech") do
        results << BetterTenant::Tenant.current
      end

      expect(results).to eq(%w[acme globex initech])
      expect(BetterTenant::Tenant.current).to be_nil
    end

    it "handles exception during request without affecting subsequent requests" do
      results = []

      # Request 1 - success
      BetterTenant::Tenant.switch("acme") do
        results << BetterTenant::Tenant.current
      end

      # Request 2 - fails
      begin
        BetterTenant::Tenant.switch("globex") do
          raise "Request failed"
        end
      rescue StandardError
        # Ignore
      end

      # Request 3 - should work normally
      BetterTenant::Tenant.switch("initech") do
        results << BetterTenant::Tenant.current
      end

      expect(results).to eq(%w[acme initech])
      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "adapter behavior" do
    it "returns nil as initial current tenant" do
      expect(BetterTenant::Tenant.current).to be_nil
    end

    it "persists tenant after switch!" do
      BetterTenant::Tenant.switch!("acme")
      expect(BetterTenant::Tenant.current).to eq("acme")

      # Tenant persists
      expect(BetterTenant::Tenant.current).to eq("acme")
    end

    it "clears tenant after reset" do
      BetterTenant::Tenant.switch!("acme")
      BetterTenant::Tenant.reset
      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "tenant validation" do
    it "validates tenant exists on switch!" do
      expect {
        BetterTenant::Tenant.switch!("nonexistent")
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end

    it "validates tenant exists on switch" do
      expect {
        BetterTenant::Tenant.switch("nonexistent") do
          # Should not reach here
        end
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end
  end

  describe "tenant names" do
    it "returns configured tenant names" do
      expect(BetterTenant::Tenant.tenant_names).to eq(%w[acme globex initech])
    end

    it "exists? returns true for valid tenants" do
      expect(BetterTenant::Tenant.exists?("acme")).to be true
      expect(BetterTenant::Tenant.exists?("globex")).to be true
    end

    it "exists? returns false for invalid tenants" do
      expect(BetterTenant::Tenant.exists?("unknown")).to be false
      expect(BetterTenant::Tenant.exists?(nil)).to be false
    end
  end

  describe "each_tenant iteration" do
    it "iterates over all tenants" do
      tenants = []
      BetterTenant::Tenant.each do |tenant|
        tenants << tenant
      end
      expect(tenants).to eq(%w[acme globex initech])
    end

    it "switches tenant context during iteration" do
      tenant_during_iteration = []
      BetterTenant::Tenant.each do |tenant|
        tenant_during_iteration << BetterTenant::Tenant.current
      end
      expect(tenant_during_iteration).to eq(%w[acme globex initech])
    end

    it "restores original tenant after iteration" do
      BetterTenant::Tenant.switch!("acme")
      BetterTenant::Tenant.each { |_t| } # Iterate
      expect(BetterTenant::Tenant.current).to eq("acme")
    end
  end

  describe "dynamic tenant names (Proc)" do
    it "supports proc for dynamic tenant names" do
      dynamic_tenants = %w[dynamic1 dynamic2]

      BetterTenant.configure do |config|
        config.strategy :column
        config.tenant_column :tenant_id
        config.tenant_names -> { dynamic_tenants }
        config.require_tenant false
      end

      expect(BetterTenant::Tenant.tenant_names).to eq(%w[dynamic1 dynamic2])

      # Modify dynamic list
      dynamic_tenants << "dynamic3"
      expect(BetterTenant::Tenant.tenant_names).to eq(%w[dynamic1 dynamic2 dynamic3])
    end
  end
end
