# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::AuditLogger do
  let(:mock_connection) { double("connection") }
  let(:logger) { instance_double(Logger) }
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :column
      c.tenant_names %w[acme globex]
      c.audit_violations true
      c.audit_access true
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

    # Configure logger
    allow(Rails).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  after do
    BetterTenant::Tenant.reset!
  end

  describe ".log_switch" do
    it "logs tenant switch when audit_access is enabled" do
      expect(logger).to receive(:info).with(/Tenant switch:.*from=nil.*to=acme/)

      described_class.log_switch(nil, "acme")
    end

    it "includes timestamp in log message" do
      expect(logger).to receive(:info).with(/\d{4}-\d{2}-\d{2}/)

      described_class.log_switch("acme", "globex")
    end
  end

  describe ".log_access" do
    it "logs tenant access when audit_access is enabled" do
      expect(logger).to receive(:info).with(/Tenant access.*acme.*Article/)

      described_class.log_access("acme", "Article", "query")
    end

    it "includes operation type in log message" do
      expect(logger).to receive(:info).with(/operation=create/)

      described_class.log_access("acme", "Article", "create")
    end
  end

  describe ".log_violation" do
    it "logs violations when audit_violations is enabled" do
      expect(logger).to receive(:warn).with(/Tenant violation/)

      described_class.log_violation(
        type: :cross_tenant_access,
        tenant: "acme",
        model: "Article",
        details: "Attempted to access record from different tenant"
      )
    end

    it "includes violation type in log message" do
      expect(logger).to receive(:warn).with(/type=cross_tenant_access/)

      described_class.log_violation(
        type: :cross_tenant_access,
        tenant: "acme",
        model: "Article"
      )
    end

    it "includes details when provided" do
      expect(logger).to receive(:warn).with(/Attempted to modify tenant_id/)

      described_class.log_violation(
        type: :immutable_tenant,
        tenant: "acme",
        model: "Article",
        details: "Attempted to modify tenant_id"
      )
    end
  end

  describe ".log_error" do
    it "logs errors at error level" do
      error = StandardError.new("Something went wrong")

      expect(logger).to receive(:error).with(/Tenant error.*Something went wrong/)

      described_class.log_error(error, tenant: "acme", model: "Article")
    end

    it "includes backtrace when available" do
      error = StandardError.new("Error with trace")
      error.set_backtrace(["line1", "line2", "line3"])

      expect(logger).to receive(:error).with(/line1/)

      described_class.log_error(error, tenant: "acme")
    end
  end

  describe "configuration-based logging" do
    context "when audit_violations is disabled" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_names %w[acme]
          c.audit_violations false
          c.audit_access false
        end
      end

      it "does not log violations" do
        expect(logger).not_to receive(:warn)

        described_class.log_violation(
          type: :cross_tenant_access,
          tenant: "acme",
          model: "Article"
        )
      end
    end

    context "when audit_access is disabled" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :column
          c.tenant_names %w[acme]
          c.audit_violations true
          c.audit_access false
        end
      end

      it "does not log access" do
        expect(logger).not_to receive(:info)

        described_class.log_access("acme", "Article", "query")
      end

      it "does not log switch" do
        expect(logger).not_to receive(:info)

        described_class.log_switch(nil, "acme")
      end
    end
  end

  describe ".format_log_entry" do
    it "formats entries as key=value pairs" do
      entry = described_class.send(:format_log_entry, {
        tenant: "acme",
        model: "Article",
        operation: "create"
      })

      expect(entry).to include("tenant=acme")
      expect(entry).to include("model=Article")
      expect(entry).to include("operation=create")
    end

    it "handles nil values" do
      entry = described_class.send(:format_log_entry, {
        tenant: nil,
        model: "Article"
      })

      # nil values are converted to empty string in the output
      expect(entry).to include("tenant=")
      expect(entry).to include("model=Article")
    end
  end
end
