# frozen_string_literal: true

Rails.application.routes.draw do
  resources :tenant_articles, only: [:index, :show, :create, :destroy]

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
