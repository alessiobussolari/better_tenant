# frozen_string_literal: true

module BetterTenant
  # Audit logger for tenant-related events and violations.
  #
  # Provides centralized logging for:
  # - Tenant switches
  # - Tenant access patterns
  # - Violations (cross-tenant access, immutable tenant changes)
  # - Errors
  #
  # @example Enable audit logging
  #   BetterTenant.configure do |config|
  #     config.audit_violations true  # Log violations
  #     config.audit_access true      # Log all access
  #   end
  #
  class AuditLogger
    class << self
      # Log a tenant switch event
      # @param from [String, nil] Previous tenant
      # @param to [String, nil] New tenant
      def log_switch(from, to)
        return unless audit_access?

        log(:info, "Tenant switch", {
          from: from || "nil",
          to: to || "nil",
          timestamp: Time.current.iso8601
        })
      end

      # Log a tenant access event
      # @param tenant [String] Current tenant
      # @param model [String] Model class name
      # @param operation [String] Operation type (query, create, update, delete)
      def log_access(tenant, model, operation)
        return unless audit_access?

        log(:info, "Tenant access", {
          tenant: tenant,
          model: model,
          operation: operation,
          timestamp: Time.current.iso8601
        })
      end

      # Log a tenant violation
      # @param type [Symbol] Violation type (:cross_tenant_access, :immutable_tenant, :missing_context)
      # @param tenant [String] Current tenant
      # @param model [String] Model class name
      # @param details [String] Additional details
      def log_violation(type:, tenant:, model:, details: nil)
        return unless audit_violations?

        log(:warn, "Tenant violation", {
          type: type,
          tenant: tenant,
          model: model,
          details: details,
          timestamp: Time.current.iso8601
        }.compact)
      end

      # Log an error
      # @param error [Exception] The error
      # @param tenant [String] Current tenant
      # @param model [String] Model class name (optional)
      def log_error(error, tenant:, model: nil)
        message_parts = {
          error_class: error.class.name,
          message: error.message,
          tenant: tenant,
          model: model,
          timestamp: Time.current.iso8601
        }.compact

        # Include first 5 lines of backtrace if available
        if error.backtrace&.any?
          message_parts[:backtrace] = error.backtrace.first(5).join(" | ")
        end

        log(:error, "Tenant error", message_parts)
      end

      private

      def audit_access?
        return false unless tenant_configured?

        Tenant.configuration[:audit_access] == true
      end

      def audit_violations?
        return false unless tenant_configured?

        Tenant.configuration[:audit_violations] == true
      end

      def tenant_configured?
        Tenant.configuration rescue false
      end

      def log(level, prefix, attributes)
        logger&.public_send(level, "[BetterTenant] #{prefix}: #{format_log_entry(attributes)}")
      end

      def format_log_entry(attributes)
        attributes.map { |k, v| "#{k}=#{v}" }.join(" ")
      end

      def logger
        Rails.logger if defined?(Rails)
      end
    end
  end
end
