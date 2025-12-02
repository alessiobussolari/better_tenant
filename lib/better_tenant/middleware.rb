# frozen_string_literal: true

module BetterTenant
  # Rack middleware for automatic tenant switching based on request.
  #
  # Like Apartment gem, this middleware wraps the entire request in a tenant
  # context, making all queries automatically scoped to the current tenant.
  # Developers don't need to call BetterTenant::Tenant.switch() manually.
  #
  # Supports multiple "elevators" for tenant detection:
  # - :subdomain - Extract from subdomain (acme.example.com -> "acme")
  # - :domain - Extract from full domain (acme.com -> "acme.com")
  # - :header - Extract from X-Tenant header
  # - :path - Extract from first path segment (example.com/acme/articles -> "acme")
  # - :generic (Proc) - Custom extraction logic
  #
  # @example Using subdomain elevator
  #   config.middleware.use BetterTenant::Middleware, :subdomain
  #
  # @example Using path elevator
  #   config.middleware.use BetterTenant::Middleware, :path
  #
  # @example Using custom elevator
  #   config.middleware.use BetterTenant::Middleware, ->(request) {
  #     request.params["tenant"]
  #   }
  #
  class Middleware
    DEFAULT_EXCLUDED_SUBDOMAINS = %w[www].freeze
    DEFAULT_EXCLUDED_PATHS = %w[api admin assets images stylesheets javascripts rails].freeze
    DEFAULT_TENANT_HEADER = "HTTP_X_TENANT"

    def initialize(app, elevator = :subdomain)
      @app = app
      @elevator = elevator
    end

    def call(env)
      request = Rack::Request.new(env)
      tenant = extract_tenant(request)

      if tenant && Tenant.exists?(tenant)
        Tenant.switch(tenant) do
          @app.call(env)
        end
      elsif tenant && !Tenant.exists?(tenant) && require_tenant?
        raise Errors::TenantNotFoundError.new(tenant_name: tenant)
      elsif !tenant && require_tenant?
        raise Errors::TenantContextMissingError.new(
          operation: "request",
          model_class: nil
        )
      else
        @app.call(env)
      end
    rescue StandardError
      Tenant.reset if Tenant.current
      raise
    end

    private

    def extract_tenant(request)
      case @elevator
      when :subdomain
        extract_subdomain(request)
      when :domain
        extract_domain(request)
      when :header
        extract_header(request)
      when :path
        extract_path(request)
      when Proc
        @elevator.call(request)
      else
        nil
      end
    end

    def extract_subdomain(request)
      host = request.host
      return nil unless host

      parts = host.split(".")
      return nil if parts.length < 3

      subdomain = parts.first
      return nil if excluded_subdomain?(subdomain)

      subdomain
    end

    def extract_domain(request)
      request.host
    end

    def extract_header(request)
      request.env[DEFAULT_TENANT_HEADER]
    end

    def extract_path(request)
      parts = request.path_info.to_s.split("/").reject(&:empty?)
      return nil if parts.empty?

      potential_tenant = parts.first
      return nil if excluded_path?(potential_tenant)

      potential_tenant
    end

    def excluded_path?(segment)
      excluded = Tenant.configuration[:excluded_paths] || []
      all_excluded = DEFAULT_EXCLUDED_PATHS + excluded
      all_excluded.include?(segment)
    end

    def excluded_subdomain?(subdomain)
      excluded = Tenant.configuration[:excluded_subdomains] || []
      all_excluded = DEFAULT_EXCLUDED_SUBDOMAINS + excluded
      all_excluded.include?(subdomain)
    end

    def require_tenant?
      Tenant.configuration[:require_tenant] == true
    end
  end
end
