# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::ActiveJobExtension do
  let(:mock_connection) { double("connection") }
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[acme globex]
      c.require_tenant false
    end
  end

  # Create a test job class
  let(:test_job_class) do
    Class.new(ActiveJob::Base) do
      include BetterTenant::ActiveJobExtension

      attr_accessor :tenant_during_perform

      def perform
        @tenant_during_perform = BetterTenant::Tenant.current
      end
    end
  end

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:execute)
    allow(mock_connection).to receive(:quote_column_name) { |name| "\"#{name}\"" }
    allow(mock_connection).to receive(:quote) { |value| "'#{value}'" }

    BetterTenant::Tenant.reset!
    BetterTenant::Tenant.configure(config)

    # Stub constant for testing
    stub_const("TestTenantJob", test_job_class)
  end

  after do
    BetterTenant::Tenant.reset!
  end

  describe "module inclusion" do
    it "adds tenant serialization methods" do
      job = TestTenantJob.new
      expect(job).to respond_to(:tenant_for_job)
      expect(job).to respond_to(:tenant_for_job=)
    end
  end

  describe "tenant serialization" do
    it "captures current tenant when job is created" do
      BetterTenant::Tenant.switch!("acme")

      job = TestTenantJob.new
      expect(job.tenant_for_job).to eq("acme")
    end

    it "does not capture tenant when none is set" do
      job = TestTenantJob.new
      expect(job.tenant_for_job).to be_nil
    end
  end

  describe "tenant restoration during perform" do
    it "switches to captured tenant during perform" do
      BetterTenant::Tenant.switch!("acme")
      job = TestTenantJob.new

      # Reset tenant before performing
      BetterTenant::Tenant.reset

      # Perform the job
      job.perform_now

      expect(job.tenant_during_perform).to eq("acme")
    end

    it "resets tenant after job completes" do
      BetterTenant::Tenant.switch!("acme")
      job = TestTenantJob.new

      BetterTenant::Tenant.reset
      job.perform_now

      expect(BetterTenant::Tenant.current).to be_nil
    end

    it "handles jobs without tenant context" do
      job = TestTenantJob.new
      job.perform_now

      expect(job.tenant_during_perform).to be_nil
    end
  end

  describe "job serialization/deserialization" do
    it "includes tenant in serialized job data" do
      BetterTenant::Tenant.switch!("acme")
      job = TestTenantJob.new

      # Use send to call private serialize method
      serialized = job.send(:serialize)
      expect(serialized["tenant_for_job"]).to eq("acme")
    end

    it "restores tenant from deserialized job data" do
      BetterTenant::Tenant.switch!("acme")
      job = TestTenantJob.new
      serialized = job.send(:serialize)

      BetterTenant::Tenant.reset

      # Deserialize through class method (as ActiveJob does)
      new_job = TestTenantJob.deserialize(serialized)

      expect(new_job.tenant_for_job).to eq("acme")
    end
  end

  describe "error handling" do
    let(:error_job_class) do
      Class.new(ActiveJob::Base) do
        include BetterTenant::ActiveJobExtension

        def perform
          raise "Job failed!"
        end
      end
    end

    before do
      stub_const("ErrorTenantJob", error_job_class)
    end

    it "resets tenant even if job raises" do
      BetterTenant::Tenant.switch!("acme")
      job = ErrorTenantJob.new

      BetterTenant::Tenant.reset

      expect {
        job.perform_now
      }.to raise_error("Job failed!")

      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "nested tenant switches" do
    let(:outer_job_class) do
      Class.new(ActiveJob::Base) do
        include BetterTenant::ActiveJobExtension

        attr_accessor :tenant_before_switch, :tenant_after_switch

        def perform
          @tenant_before_switch = BetterTenant::Tenant.current
          # Simulate a nested tenant switch
          BetterTenant::Tenant.switch("globex") do
            # Inside switch to different tenant
          end
          @tenant_after_switch = BetterTenant::Tenant.current
        end
      end
    end

    before do
      stub_const("OuterTenantJob", outer_job_class)
    end

    it "maintains job tenant context after nested switch" do
      BetterTenant::Tenant.switch!("acme")
      job = OuterTenantJob.new

      job.perform_now

      expect(job.tenant_before_switch).to eq("acme")
      # After nested switch completes, original tenant should be restored
      expect(job.tenant_after_switch).to eq("acme")
    end
  end
end
