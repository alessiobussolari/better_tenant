# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-12-01

### Added

- Initial release extracted from BetterModel gem
- Column-based multi-tenancy strategy
- Schema-based multi-tenancy strategy (PostgreSQL)
- Rack middleware with multiple elevators:
  - `:header` - X-Tenant header
  - `:subdomain` - subdomain extraction
  - `:domain` - full domain matching
  - `:path` - URL path extraction
  - `:host` - hostname matching
  - `:generic` - custom extraction
- ActiveRecord extension for automatic tenant scoping
- ActiveJob extension for tenant context preservation
- Audit logging for tenant operations
- Rake tasks for tenant management
- Rails generator for installation
