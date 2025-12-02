# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Adapters::ColumnAdapter do
  let(:config) do
    {
      strategy: :column,
      tenant_column: :tenant_id,
      tenant_names: %w[acme globex],
      excluded_models: [],
      callbacks: {
        before_create: nil,
        after_create: nil,
        before_switch: nil,
        after_switch: nil
      }
    }
  end

  subject(:adapter) { described_class.new(config) }

  describe "inheritance" do
    it "inherits from AbstractAdapter" do
      expect(described_class).to be < BetterTenant::Adapters::AbstractAdapter
    end
  end

  describe "#initialize" do
    it "stores the configuration" do
      expect(adapter.config).to eq(config)
    end

    it "starts with no current tenant" do
      expect(adapter.current).to be_nil
    end
  end

  describe "#switch!" do
    context "with valid tenant" do
      it "sets the current tenant" do
        adapter.switch!("acme")
        expect(adapter.current).to eq("acme")
      end

      it "returns the tenant name" do
        result = adapter.switch!("acme")
        expect(result).to eq("acme")
      end
    end

    context "with invalid tenant" do
      it "raises TenantNotFoundError" do
        expect {
          adapter.switch!("unknown")
        }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
      end
    end

    context "with callbacks" do
      let(:before_callback) { double("before_callback") }
      let(:after_callback) { double("after_callback") }
      let(:config) do
        super().merge(
          callbacks: {
            before_switch: ->(from, to) { before_callback.call(from, to) },
            after_switch: ->(from, to) { after_callback.call(from, to) }
          }
        )
      end

      it "calls before_switch callback" do
        expect(before_callback).to receive(:call).with(nil, "acme")
        allow(after_callback).to receive(:call)
        adapter.switch!("acme")
      end

      it "calls after_switch callback" do
        allow(before_callback).to receive(:call)
        expect(after_callback).to receive(:call).with(nil, "acme")
        adapter.switch!("acme")
      end
    end
  end

  describe "#switch" do
    it "switches tenant for block duration" do
      adapter.switch("acme") do
        expect(adapter.current).to eq("acme")
      end
    end

    it "resets tenant after block" do
      adapter.switch("acme") { }
      expect(adapter.current).to be_nil
    end

    it "resets tenant even if block raises" do
      expect {
        adapter.switch("acme") do
          raise "test error"
        end
      }.to raise_error("test error")

      expect(adapter.current).to be_nil
    end

    it "returns the block result" do
      result = adapter.switch("acme") { "block result" }
      expect(result).to eq("block result")
    end
  end

  describe "#reset" do
    before { adapter.switch!("acme") }

    it "clears the current tenant" do
      adapter.reset
      expect(adapter.current).to be_nil
    end
  end

  describe "#exists?" do
    it "returns true for existing tenant" do
      expect(adapter.exists?("acme")).to be true
    end

    it "returns false for non-existing tenant" do
      expect(adapter.exists?("unknown")).to be false
    end
  end

  describe "#create" do
    it "validates tenant name" do
      config[:tenant_names] << "new_tenant"
      expect { adapter.create("new_tenant") }.not_to raise_error
    end

    context "with callbacks" do
      let(:before_callback) { double("before_callback") }
      let(:after_callback) { double("after_callback") }
      let(:config) do
        super().merge(
          tenant_names: %w[acme globex new_tenant],
          callbacks: {
            before_create: ->(tenant) { before_callback.call(tenant) },
            after_create: ->(tenant) { after_callback.call(tenant) }
          }
        )
      end

      it "calls before_create callback" do
        expect(before_callback).to receive(:call).with("new_tenant")
        allow(after_callback).to receive(:call)
        adapter.create("new_tenant")
      end

      it "calls after_create callback" do
        allow(before_callback).to receive(:call)
        expect(after_callback).to receive(:call).with("new_tenant")
        adapter.create("new_tenant")
      end
    end
  end

  describe "#drop" do
    it "runs callbacks without actually dropping anything (no schema in column strategy)" do
      expect { adapter.drop("acme") }.not_to raise_error
    end
  end

  describe "#each_tenant" do
    it "iterates over all tenants" do
      tenants = []
      adapter.each_tenant { |t| tenants << t }
      expect(tenants).to eq(%w[acme globex])
    end

    it "switches to each tenant during iteration" do
      current_tenants = []
      adapter.each_tenant { current_tenants << adapter.current }
      expect(current_tenants).to eq(%w[acme globex])
    end

    it "resets tenant after iteration" do
      adapter.each_tenant { }
      expect(adapter.current).to be_nil
    end
  end

  describe "#tenant_column" do
    it "returns the configured tenant column" do
      expect(adapter.tenant_column).to eq(:tenant_id)
    end
  end
end
