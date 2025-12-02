# frozen_string_literal: true

module BetterTenant
  module Errors
    # Configuration error for BetterTenant module.
    # Inherits from ArgumentError for backward compatibility.
    class ConfigurationError < ArgumentError
    end
  end
end
