# frozen_string_literal: true

class AddTenantIdToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :tenant_id, :string
    add_index :articles, :tenant_id
  end
end
