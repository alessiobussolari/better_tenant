# frozen_string_literal: true

class TenantArticlesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    @articles = TenantArticle.all
    render json: @articles
  end

  def show
    @article = TenantArticle.find(params[:id])
    render json: @article
  end

  def create
    @article = TenantArticle.create!(article_params)
    render json: @article, status: :created
  end

  def destroy
    @article = TenantArticle.find(params[:id])
    @article.destroy
    head :no_content
  end

  private

  def article_params
    params.permit(:title, :content, :status)
  end
end
