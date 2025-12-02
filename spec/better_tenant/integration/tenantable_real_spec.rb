# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BetterTenant Real Integration", type: :model do
  let(:config) do
    BetterTenant::Configurator.new.tap do |c|
      c.strategy :column
      c.tenant_column :tenant_id
      c.tenant_names %w[acme globex initech]
      c.require_tenant false
      c.strict_mode true  # Enable immutability check
    end
  end

  before(:all) do
    # Ensure TenantArticle is loaded
    TenantArticle.reset_column_information
  end

  before(:each) do
    BetterTenant::Tenant.reset!
    BetterTenant::Tenant.configure(config)
    # Clean up any existing tenant articles
    TenantArticle.unscoped.delete_all
  end

  after(:each) do
    BetterTenant::Tenant.reset!
  end

  describe "data isolation between tenants" do
    it "isolates data between tenants" do
      # Create article in tenant acme
      BetterTenant::Tenant.switch("acme") do
        TenantArticle.create!(title: "Acme Article")
      end

      # Create article in tenant globex
      BetterTenant::Tenant.switch("globex") do
        TenantArticle.create!(title: "Globex Article")
      end

      # Verify isolation - acme sees only acme's article
      BetterTenant::Tenant.switch("acme") do
        expect(TenantArticle.count).to eq(1)
        expect(TenantArticle.first.title).to eq("Acme Article")
      end

      # Verify isolation - globex sees only globex's article
      BetterTenant::Tenant.switch("globex") do
        expect(TenantArticle.count).to eq(1)
        expect(TenantArticle.first.title).to eq("Globex Article")
      end

      # Verify total count without tenant (should see all)
      TenantArticle.unscoped_tenant do
        expect(TenantArticle.count).to eq(2)
      end
    end

    it "does not find records from other tenants" do
      acme_article = nil

      BetterTenant::Tenant.switch("acme") do
        acme_article = TenantArticle.create!(title: "Acme Secret")
      end

      BetterTenant::Tenant.switch("globex") do
        # find_by should return nil for other tenant's record
        expect(TenantArticle.find_by(id: acme_article.id)).to be_nil

        # where should return empty
        expect(TenantArticle.where(id: acme_article.id).count).to eq(0)
      end
    end
  end

  describe "automatic tenant_id assignment" do
    it "auto-assigns tenant_id on create" do
      BetterTenant::Tenant.switch("acme") do
        article = TenantArticle.create!(title: "Auto Tenant")
        expect(article.tenant_id).to eq("acme")
      end
    end

    it "auto-assigns tenant_id on new record initialize" do
      BetterTenant::Tenant.switch("globex") do
        article = TenantArticle.new(title: "New Article")
        expect(article.tenant_id).to eq("globex")
      end
    end

    it "does not override explicit tenant_id" do
      BetterTenant::Tenant.switch("acme") do
        article = TenantArticle.new(title: "Explicit", tenant_id: "globex")
        # The explicit tenant_id should be preserved
        expect(article.tenant_id).to eq("globex")
      end
    end
  end

  describe "tenant_id immutability" do
    it "prevents changing tenant_id after creation" do
      article = nil

      BetterTenant::Tenant.switch("acme") do
        article = TenantArticle.create!(title: "Immutable Test")
      end

      BetterTenant::Tenant.switch("acme") do
        article.tenant_id = "globex"
        expect { article.save! }.to raise_error(
          BetterTenant::Errors::TenantImmutableError
        )
      end
    end

    it "allows saving without changing tenant_id" do
      BetterTenant::Tenant.switch("acme") do
        article = TenantArticle.create!(title: "Original Title")
        article.title = "Updated Title"
        expect { article.save! }.not_to raise_error
        expect(article.reload.title).to eq("Updated Title")
      end
    end
  end

  describe "query scoping" do
    before do
      BetterTenant::Tenant.switch("acme") do
        3.times { |i| TenantArticle.create!(title: "Acme #{i}") }
      end

      BetterTenant::Tenant.switch("globex") do
        2.times { |i| TenantArticle.create!(title: "Globex #{i}") }
      end
    end

    it "scopes all queries to current tenant" do
      BetterTenant::Tenant.switch("acme") do
        expect(TenantArticle.count).to eq(3)
        expect(TenantArticle.all.map(&:tenant_id).uniq).to eq(["acme"])
      end
    end

    it "scopes where queries to current tenant" do
      BetterTenant::Tenant.switch("globex") do
        results = TenantArticle.where("title LIKE ?", "%Globex%")
        expect(results.count).to eq(2)
      end
    end

    it "scopes order queries to current tenant" do
      BetterTenant::Tenant.switch("acme") do
        results = TenantArticle.order(:title)
        expect(results.count).to eq(3)
        expect(results.all? { |a| a.tenant_id == "acme" }).to be true
      end
    end
  end

  describe "tenant switch with block" do
    it "automatically resets tenant after block" do
      BetterTenant::Tenant.switch!("acme")
      expect(BetterTenant::Tenant.current).to eq("acme")

      BetterTenant::Tenant.switch("globex") do
        expect(BetterTenant::Tenant.current).to eq("globex")
      end

      # Should be back to acme after block
      expect(BetterTenant::Tenant.current).to eq("acme")
    end

    it "resets tenant even on exception" do
      BetterTenant::Tenant.switch!("acme")

      expect {
        BetterTenant::Tenant.switch("globex") do
          raise StandardError, "Test error"
        end
      }.to raise_error(StandardError, "Test error")

      # Should be back to acme after exception
      expect(BetterTenant::Tenant.current).to eq("acme")
    end
  end

  describe "unscoped_tenant bypass" do
    before do
      BetterTenant::Tenant.switch("acme") do
        TenantArticle.create!(title: "Acme Article")
      end

      BetterTenant::Tenant.switch("globex") do
        TenantArticle.create!(title: "Globex Article")
      end
    end

    it "allows accessing all records without tenant context" do
      TenantArticle.unscoped_tenant do
        expect(TenantArticle.count).to eq(2)
      end
    end

    it "returns to previous tenant after block" do
      BetterTenant::Tenant.switch!("acme")

      TenantArticle.unscoped_tenant do
        expect(TenantArticle.count).to eq(2)
      end

      expect(TenantArticle.count).to eq(1)
      expect(BetterTenant::Tenant.current).to eq("acme")
    end
  end

  describe "multiple operations in same tenant context" do
    it "maintains tenant context across multiple operations" do
      BetterTenant::Tenant.switch("initech") do
        # Create
        article = TenantArticle.create!(title: "First")
        expect(article.tenant_id).to eq("initech")

        # Read
        found = TenantArticle.find(article.id)
        expect(found.tenant_id).to eq("initech")

        # Update
        found.update!(title: "Updated")
        expect(found.reload.title).to eq("Updated")
        expect(found.tenant_id).to eq("initech")

        # Create another
        another = TenantArticle.create!(title: "Second")
        expect(another.tenant_id).to eq("initech")

        # Count
        expect(TenantArticle.count).to eq(2)
      end
    end
  end

  describe "error handling" do
    it "raises TenantNotFoundError for unknown tenant" do
      expect {
        BetterTenant::Tenant.switch("unknown_tenant") do
          TenantArticle.create!(title: "Should fail")
        end
      }.to raise_error(BetterTenant::Errors::TenantNotFoundError)
    end
  end

  describe "integration with ActiveRecord callbacks" do
    it "sets tenant_id before validation" do
      BetterTenant::Tenant.switch("acme") do
        article = TenantArticle.new(title: "Callback Test")
        article.valid?
        expect(article.tenant_id).to eq("acme")
      end
    end

    it "persists tenant_id through save callbacks" do
      BetterTenant::Tenant.switch("globex") do
        article = TenantArticle.new(title: "Persist Test")
        article.save!

        # Reload from database
        reloaded = TenantArticle.find(article.id)
        expect(reloaded.tenant_id).to eq("globex")
      end
    end
  end

  describe "nested tenant switches" do
    it "handles nested switch blocks correctly" do
      BetterTenant::Tenant.switch("acme") do
        TenantArticle.create!(title: "Acme Outer")
        expect(TenantArticle.count).to eq(1)

        BetterTenant::Tenant.switch("globex") do
          TenantArticle.create!(title: "Globex Inner")
          expect(TenantArticle.count).to eq(1)
        end

        # Back to acme context
        expect(TenantArticle.count).to eq(1)
        expect(TenantArticle.first.title).to eq("Acme Outer")
      end
    end
  end
end
