# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterTenant::Middleware do
  let(:mock_connection) { double("connection") }
  let(:app) { ->(env) { [200, env, "OK"] } }
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :schema
      c.tenant_names %w[acme globex]
      c.persistent_schemas %w[shared]
      c.schema_format "tenant_%{tenant}"
      c.require_tenant false  # Default: don't require tenant
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

  describe "with subdomain elevator" do
    let(:middleware) { described_class.new(app, :subdomain) }

    it "extracts tenant from subdomain" do
      env = Rack::MockRequest.env_for("http://acme.example.com/")
      middleware.call(env)

      # After call completes, tenant should be reset
      expect(BetterTenant::Tenant.current).to be_nil
    end

    it "switches tenant during request" do
      env = Rack::MockRequest.env_for("http://acme.example.com/")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :subdomain).call(env)
      expect(tenant_during_request).to eq("acme")
    end

    it "ignores requests without subdomain" do
      env = Rack::MockRequest.env_for("http://example.com/")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :subdomain).call(env)
      expect(tenant_during_request).to be_nil
    end

    it "ignores www subdomain" do
      env = Rack::MockRequest.env_for("http://www.example.com/")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :subdomain).call(env)
      expect(tenant_during_request).to be_nil
    end

    context "with excluded_subdomains" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex admin]
          c.excluded_subdomains %w[admin api]
          c.require_tenant false
        end
      end

      it "ignores excluded subdomains" do
        env = Rack::MockRequest.env_for("http://admin.example.com/")
        tenant_during_request = nil

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :subdomain).call(env)
        expect(tenant_during_request).to be_nil
      end
    end
  end

  describe "with domain elevator" do
    let(:config) do
      BetterTenant::Configurator.new.tap do |c|
        c.strategy :schema
        c.tenant_names %w[acme.com globex.com]
        c.require_tenant false
      end
    end

    it "extracts tenant from full domain" do
      env = Rack::MockRequest.env_for("http://acme.com/")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :domain).call(env)
      expect(tenant_during_request).to eq("acme.com")
    end
  end

  describe "with header elevator" do
    let(:middleware) { described_class.new(app, :header) }

    it "extracts tenant from X-Tenant header" do
      env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "acme")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :header).call(env)
      expect(tenant_during_request).to eq("acme")
    end

    it "ignores requests without header" do
      env = Rack::MockRequest.env_for("http://example.com/")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :header).call(env)
      expect(tenant_during_request).to be_nil
    end
  end

  describe "with generic elevator (proc)" do
    it "extracts tenant using custom proc" do
      custom_elevator = ->(request) { request.params["tenant"] }
      env = Rack::MockRequest.env_for("http://example.com/?tenant=acme")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, custom_elevator).call(env)
      expect(tenant_during_request).to eq("acme")
    end

    context "edge cases" do
      it "handles proc that returns nil" do
        custom_elevator = ->(_request) { nil }
        env = Rack::MockRequest.env_for("http://example.com/")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, custom_elevator).call(env)
        expect(tenant_during_request).to be_nil
      end

      it "handles proc that raises exception" do
        custom_elevator = ->(_request) { raise StandardError, "extraction failed" }
        env = Rack::MockRequest.env_for("http://example.com/")

        expect {
          described_class.new(app, custom_elevator).call(env)
        }.to raise_error(StandardError, "extraction failed")
      end

      it "handles proc that returns invalid tenant name" do
        config_with_require = BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex]
          c.persistent_schemas %w[shared]
          c.schema_format "tenant_%{tenant}"
          c.require_tenant true
        end
        BetterTenant::Tenant.reset!
        BetterTenant::Tenant.configure(config_with_require)

        custom_elevator = ->(_request) { "nonexistent_tenant" }
        env = Rack::MockRequest.env_for("http://example.com/")

        expect {
          described_class.new(app, custom_elevator).call(env)
        }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
      end

      it "handles proc that returns empty string" do
        custom_elevator = ->(_request) { "" }
        env = Rack::MockRequest.env_for("http://example.com/")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, custom_elevator).call(env)
        expect(tenant_during_request).to be_nil
      end
    end
  end

  describe "with path elevator" do
    it "extracts tenant from first path segment" do
      env = Rack::MockRequest.env_for("http://example.com/acme/articles")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :path).call(env)
      expect(tenant_during_request).to eq("acme")
    end

    it "ignores requests to root path" do
      env = Rack::MockRequest.env_for("http://example.com/")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :path).call(env)
      expect(tenant_during_request).to be_nil
    end

    it "ignores excluded paths like /api" do
      env = Rack::MockRequest.env_for("http://example.com/api/v1/users")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :path).call(env)
      expect(tenant_during_request).to be_nil
    end

    it "ignores excluded paths like /admin" do
      env = Rack::MockRequest.env_for("http://example.com/admin/dashboard")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :path).call(env)
      expect(tenant_during_request).to be_nil
    end

    it "ignores excluded paths like /assets" do
      env = Rack::MockRequest.env_for("http://example.com/assets/application.js")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :path).call(env)
      expect(tenant_during_request).to be_nil
    end

    context "with custom excluded_paths" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex webhooks]
          c.excluded_paths %w[webhooks health]
          c.require_tenant false
        end
      end

      it "ignores custom excluded paths" do
        env = Rack::MockRequest.env_for("http://example.com/webhooks/stripe")
        tenant_during_request = nil

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :path).call(env)
        expect(tenant_during_request).to be_nil
      end

      it "ignores health check path" do
        env = Rack::MockRequest.env_for("http://example.com/health")
        tenant_during_request = nil

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :path).call(env)
        expect(tenant_during_request).to be_nil
      end
    end
  end

  describe "error handling" do
    it "resets tenant even if app raises" do
      error_app = ->(_env) { raise "Test error" }
      env = Rack::MockRequest.env_for("http://acme.example.com/")

      middleware = described_class.new(error_app, :subdomain)

      expect { middleware.call(env) }.to raise_error("Test error")
      expect(BetterTenant::Tenant.current).to be_nil
    end
  end

  describe "invalid tenant handling" do
    context "when require_tenant is false (default)" do
      it "continues without tenant when tenant not found" do
        env = Rack::MockRequest.env_for("http://unknown.example.com/")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :subdomain).call(env)
        expect(tenant_during_request).to be_nil
      end
    end

    context "when require_tenant is true" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex]
          c.require_tenant true
        end
      end

      it "raises TenantNotFoundError for unknown tenant" do
        env = Rack::MockRequest.env_for("http://unknown.example.com/")

        expect {
          described_class.new(app, :subdomain).call(env)
        }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
      end

      it "raises TenantContextMissingError when no tenant detected" do
        env = Rack::MockRequest.env_for("http://example.com/")

        expect {
          described_class.new(app, :subdomain).call(env)
        }.to raise_error(BetterTenant::Errors::TenantContextMissingError)
      end
    end
  end

  describe "default elevator" do
    it "defaults to :subdomain when no elevator specified" do
      env = Rack::MockRequest.env_for("http://acme.example.com/")
      tenant_during_request = nil

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app).call(env)
      expect(tenant_during_request).to eq("acme")
    end
  end

  describe "invalid elevator type" do
    it "returns nil for unknown elevator symbol" do
      env = Rack::MockRequest.env_for("http://acme.example.com/")
      tenant_during_request = :not_set

      test_app = lambda do |e|
        tenant_during_request = BetterTenant::Tenant.current
        [200, e, "OK"]
      end

      described_class.new(test_app, :unknown_elevator).call(env)
      expect(tenant_during_request).to be_nil
    end
  end

  describe "edge cases" do
    describe "unicode and special characters" do
      let(:config) do
        BetterTenant::Configurator.new.tap do |c|
          c.strategy :schema
          c.tenant_names %w[acme globex tenant-with-dash tenant_with_underscore]
          c.require_tenant false
        end
      end

      it "handles tenant names with hyphens" do
        env = Rack::MockRequest.env_for("http://tenant-with-dash.example.com/")
        tenant_during_request = nil

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :subdomain).call(env)
        expect(tenant_during_request).to eq("tenant-with-dash")
      end

      it "handles tenant names with underscores in headers" do
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "tenant_with_underscore")
        tenant_during_request = nil

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :header).call(env)
        expect(tenant_during_request).to eq("tenant_with_underscore")
      end

      it "handles unicode subdomain gracefully" do
        # URI library requires ASCII-only URIs, so we set HTTP_HOST directly
        env = Rack::MockRequest.env_for("http://example.com/")
        env["HTTP_HOST"] = "テスト.example.com"
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :subdomain).call(env)
        # Unicode subdomain won't match any tenant, should be nil
        expect(tenant_during_request).to be_nil
      end

      it "handles unicode header values gracefully" do
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "テスト")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :header).call(env)
        # Unicode tenant won't match any tenant, should be nil
        expect(tenant_during_request).to be_nil
      end
    end

    describe "long inputs" do
      it "handles very long subdomain" do
        long_subdomain = "a" * 255
        env = Rack::MockRequest.env_for("http://#{long_subdomain}.example.com/")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :subdomain).call(env)
        expect(tenant_during_request).to be_nil
      end

      it "handles very long header value" do
        long_tenant = "a" * 1000
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => long_tenant)
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :header).call(env)
        expect(tenant_during_request).to be_nil
      end

      it "handles very long path segment" do
        long_segment = "a" * 1000
        env = Rack::MockRequest.env_for("http://example.com/#{long_segment}/articles")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :path).call(env)
        expect(tenant_during_request).to be_nil
      end
    end

    describe "malformed inputs" do
      it "handles nil host" do
        env = { "HTTP_HOST" => nil, "PATH_INFO" => "/" }
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        expect {
          described_class.new(test_app, :subdomain).call(env)
        }.not_to raise_error
      end

      it "handles empty host" do
        env = { "HTTP_HOST" => "", "PATH_INFO" => "/" }
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        expect {
          described_class.new(test_app, :subdomain).call(env)
        }.not_to raise_error
      end

      it "handles malformed URL with special characters" do
        env = Rack::MockRequest.env_for("http://example.com/")
        env["HTTP_HOST"] = "acme<script>.example.com"
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :subdomain).call(env)
        # Malformed subdomain won't match, should be nil
        expect(tenant_during_request).to be_nil
      end

      it "handles header with whitespace" do
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "  acme  ")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :header).call(env)
        # Whitespace-padded tenant won't match without stripping
        expect(tenant_during_request).to be_nil
      end
    end

    describe "case sensitivity" do
      it "tenant matching is case-sensitive for subdomains" do
        env = Rack::MockRequest.env_for("http://ACME.example.com/")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :subdomain).call(env)
        # ACME != acme (case sensitive)
        expect(tenant_during_request).to be_nil
      end

      it "tenant matching is case-sensitive for headers" do
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "ACME")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :header).call(env)
        # ACME != acme (case sensitive)
        expect(tenant_during_request).to be_nil
      end
    end

    describe "concurrent requests" do
      it "maintains tenant isolation between requests" do
        results = []

        test_app = lambda do |e|
          results << BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        middleware = described_class.new(test_app, :header)

        # Simulate sequential requests
        env1 = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "acme")
        env2 = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "globex")

        middleware.call(env1)
        middleware.call(env2)

        expect(results).to eq(%w[acme globex])
      end

      it "properly resets tenant after each request" do
        tenant_after_request = :not_set

        test_app = lambda do |e|
          [200, e, "OK"]
        end

        middleware = described_class.new(test_app, :header)
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "acme")

        middleware.call(env)
        tenant_after_request = BetterTenant::Tenant.current

        expect(tenant_after_request).to be_nil
      end
    end

    describe "response preservation" do
      it "preserves response status" do
        test_app = ->(_env) { [404, {}, "Not Found"] }
        middleware = described_class.new(test_app, :header)
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "acme")

        status, = middleware.call(env)
        expect(status).to eq(404)
      end

      it "preserves response headers" do
        test_app = ->(_env) { [200, { "X-Custom" => "value" }, "OK"] }
        middleware = described_class.new(test_app, :header)
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "acme")

        _, headers, = middleware.call(env)
        expect(headers["X-Custom"]).to eq("value")
      end

      it "preserves response body" do
        test_app = ->(_env) { [200, {}, "Custom Body"] }
        middleware = described_class.new(test_app, :header)
        env = Rack::MockRequest.env_for("http://example.com/", "HTTP_X_TENANT" => "acme")

        _, _, body = middleware.call(env)
        expect(body).to eq("Custom Body")
      end
    end

    describe "unsupported elevators" do
      it "returns nil for :host elevator (not implemented)" do
        # :host elevator is not implemented, so it returns nil
        env = Rack::MockRequest.env_for("http://acme.example.com/")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :host).call(env)
        expect(tenant_during_request).to be_nil
      end

      it "returns nil for any unknown elevator symbol" do
        env = Rack::MockRequest.env_for("http://acme.example.com/")
        tenant_during_request = :not_set

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :custom_unknown).call(env)
        expect(tenant_during_request).to be_nil
      end
    end

    describe "path with query parameters" do
      it "extracts tenant from path ignoring query string" do
        env = Rack::MockRequest.env_for("http://example.com/acme/articles?page=1&sort=created")
        tenant_during_request = nil

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :path).call(env)
        expect(tenant_during_request).to eq("acme")
      end

      it "handles path with fragment" do
        env = Rack::MockRequest.env_for("http://example.com/acme/articles#section1")
        tenant_during_request = nil

        test_app = lambda do |e|
          tenant_during_request = BetterTenant::Tenant.current
          [200, e, "OK"]
        end

        described_class.new(test_app, :path).call(env)
        expect(tenant_during_request).to eq("acme")
      end
    end
  end
end
