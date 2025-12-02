# frozen_string_literal: true

# Model for testing BetterTenant module with real database operations.
class TenantArticle < ApplicationRecord
  self.table_name = "articles"

  include BetterTenant::ActiveRecordExtension
end
