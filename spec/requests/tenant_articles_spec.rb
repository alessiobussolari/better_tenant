# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TenantArticles Controller", type: :request do
  before(:each) do
    # Clean tenant articles but don't reset tenant configuration
    # (configured globally in rails_helper.rb)
    TenantArticle.unscoped.delete_all
  end

  describe "tenant isolation via header" do
    it "creates articles scoped to tenant from X-Tenant header" do
      post "/tenant_articles",
        params: { title: "Acme Article" },
        headers: { "X-Tenant" => "acme" }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["tenant_id"]).to eq("acme")
    end

    it "returns only articles for current tenant" do
      # Setup: creo articoli per tenant diversi
      BetterTenant::Tenant.switch("acme") do
        TenantArticle.create!(title: "Acme Article 1")
        TenantArticle.create!(title: "Acme Article 2")
      end

      BetterTenant::Tenant.switch("globex") do
        TenantArticle.create!(title: "Globex Article")
      end

      # Request come tenant acme
      get "/tenant_articles", headers: { "X-Tenant" => "acme" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
      expect(json.map { |a| a["title"] }).to all(start_with("Acme"))
    end

    it "isolates data between tenants - cannot see other tenant's articles" do
      # Creo articolo come acme
      post "/tenant_articles",
        params: { title: "Secret Acme Data" },
        headers: { "X-Tenant" => "acme" }
      acme_article_id = JSON.parse(response.body)["id"]

      # Tento di accedervi come globex
      get "/tenant_articles/#{acme_article_id}",
        headers: { "X-Tenant" => "globex" }

      expect(response).to have_http_status(:not_found)
    end

    it "cannot delete articles from other tenants" do
      # Creo articolo come acme
      acme_article = nil
      BetterTenant::Tenant.switch("acme") do
        acme_article = TenantArticle.create!(title: "Acme Protected")
      end

      # Tento di eliminarlo come globex
      delete "/tenant_articles/#{acme_article.id}",
        headers: { "X-Tenant" => "globex" }

      expect(response).to have_http_status(:not_found)

      # Verifico che esiste ancora
      BetterTenant::Tenant.switch("acme") do
        expect(TenantArticle.find_by(id: acme_article.id)).to be_present
      end
    end

    it "each tenant has its own data set" do
      # Creo articoli per 3 tenant diversi
      BetterTenant::Tenant.switch("acme") do
        TenantArticle.create!(title: "Acme 1")
        TenantArticle.create!(title: "Acme 2")
      end

      BetterTenant::Tenant.switch("globex") do
        TenantArticle.create!(title: "Globex 1")
      end

      BetterTenant::Tenant.switch("initech") do
        TenantArticle.create!(title: "Initech 1")
        TenantArticle.create!(title: "Initech 2")
        TenantArticle.create!(title: "Initech 3")
      end

      # Verifico count per ogni tenant
      get "/tenant_articles", headers: { "X-Tenant" => "acme" }
      expect(JSON.parse(response.body).size).to eq(2)

      get "/tenant_articles", headers: { "X-Tenant" => "globex" }
      expect(JSON.parse(response.body).size).to eq(1)

      get "/tenant_articles", headers: { "X-Tenant" => "initech" }
      expect(JSON.parse(response.body).size).to eq(3)
    end
  end

  describe "tenant switching during request" do
    it "maintains tenant context throughout request" do
      # Creo articoli come acme
      post "/tenant_articles",
        params: { title: "First" },
        headers: { "X-Tenant" => "acme" }

      post "/tenant_articles",
        params: { title: "Second" },
        headers: { "X-Tenant" => "acme" }

      # Verifico che index restituisce entrambi
      get "/tenant_articles", headers: { "X-Tenant" => "acme" }

      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
    end

    it "resets tenant after each request" do
      # Prima request come acme
      post "/tenant_articles",
        params: { title: "Acme" },
        headers: { "X-Tenant" => "acme" }

      # Seconda request come globex
      post "/tenant_articles",
        params: { title: "Globex" },
        headers: { "X-Tenant" => "globex" }

      # Verifico isolamento
      get "/tenant_articles", headers: { "X-Tenant" => "acme" }
      acme_articles = JSON.parse(response.body)

      get "/tenant_articles", headers: { "X-Tenant" => "globex" }
      globex_articles = JSON.parse(response.body)

      expect(acme_articles.size).to eq(1)
      expect(globex_articles.size).to eq(1)
      expect(acme_articles.first["title"]).to eq("Acme")
      expect(globex_articles.first["title"]).to eq("Globex")
    end
  end

  describe "without tenant header" do
    context "when require_tenant is false" do
      it "allows requests without tenant" do
        get "/tenant_articles"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "multiple operations same tenant" do
    it "performs CRUD within tenant context" do
      headers = { "X-Tenant" => "initech" }

      # Create
      post "/tenant_articles",
        params: { title: "Initech Report" },
        headers: headers
      expect(response).to have_http_status(:created)
      article_id = JSON.parse(response.body)["id"]

      # Read
      get "/tenant_articles/#{article_id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["title"]).to eq("Initech Report")

      # Index
      get "/tenant_articles", headers: headers
      expect(JSON.parse(response.body).size).to eq(1)

      # Delete
      delete "/tenant_articles/#{article_id}", headers: headers
      expect(response).to have_http_status(:no_content)

      # Verify deleted
      get "/tenant_articles", headers: headers
      expect(JSON.parse(response.body).size).to eq(0)
    end
  end

  describe "cross-tenant security" do
    it "prevents reading other tenant's specific article" do
      # Creo articolo per acme
      acme_article = nil
      BetterTenant::Tenant.switch("acme") do
        acme_article = TenantArticle.create!(title: "Acme Secret")
      end

      # Provo a leggerlo da globex
      get "/tenant_articles/#{acme_article.id}",
        headers: { "X-Tenant" => "globex" }

      expect(response).to have_http_status(:not_found)
    end

    it "auto-assigns correct tenant_id on create" do
      # Creo come acme
      post "/tenant_articles",
        params: { title: "Test" },
        headers: { "X-Tenant" => "acme" }

      article = TenantArticle.unscoped.last
      expect(article.tenant_id).to eq("acme")

      # Creo come globex
      post "/tenant_articles",
        params: { title: "Test 2" },
        headers: { "X-Tenant" => "globex" }

      article2 = TenantArticle.unscoped.last
      expect(article2.tenant_id).to eq("globex")
    end
  end

  describe "database verification" do
    it "stores all tenant articles in same table with different tenant_id" do
      # Creo articoli per diversi tenant
      post "/tenant_articles",
        params: { title: "Acme Article" },
        headers: { "X-Tenant" => "acme" }

      post "/tenant_articles",
        params: { title: "Globex Article" },
        headers: { "X-Tenant" => "globex" }

      # Verifico nel database direttamente (bypassing tenant scope)
      all_articles = TenantArticle.unscoped.all
      expect(all_articles.count).to eq(2)

      tenant_ids = all_articles.pluck(:tenant_id).uniq.sort
      expect(tenant_ids).to eq(%w[acme globex])
    end
  end
end
