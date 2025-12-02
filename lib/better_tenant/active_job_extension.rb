# frozen_string_literal: true

module BetterTenant
  # ActiveJob extension for automatic tenant serialization.
  #
  # When included in a job, this module:
  # - Captures the current tenant when the job is created
  # - Restores the tenant context when the job is performed
  # - Ensures tenant is reset after job completes
  #
  # @example
  #   class ProcessOrderJob < ApplicationJob
  #     include BetterTenant::ActiveJobExtension
  #
  #     def perform(order_id)
  #       # Tenant context is automatically restored
  #       order = Order.find(order_id)
  #       order.process!
  #     end
  #   end
  #
  #   # When enqueueing:
  #   BetterTenant::Tenant.switch("acme") do
  #     ProcessOrderJob.perform_later(order.id)
  #     # Job will be performed in "acme" tenant context
  #   end
  #
  module ActiveJobExtension
    extend ActiveSupport::Concern

    included do
      # Capture tenant when job is initialized
      attr_accessor :tenant_for_job

      # Hook into job lifecycle
      around_perform :with_tenant_context
    end

    # Override initialize to capture tenant
    def initialize(*args, **kwargs, &block)
      super
      @tenant_for_job = Tenant.current if tenant_configured?
    end

    private

    # Wrap job execution in tenant context
    def with_tenant_context
      if tenant_for_job && tenant_configured?
        Tenant.switch(tenant_for_job) { yield }
      else
        yield
      end
    end

    # Check if tenant is configured
    def tenant_configured?
      Tenant.configuration rescue false
    end

    class_methods do
      # Override deserialize to restore tenant
      def deserialize(job_data)
        job = super
        job.tenant_for_job = job_data["tenant_for_job"] if job_data.key?("tenant_for_job")
        job
      end
    end

    # Override serialize to include tenant
    def serialize
      super.merge("tenant_for_job" => tenant_for_job)
    end
  end
end
