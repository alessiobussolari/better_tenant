# frozen_string_literal: true

require_relative "lib/better_tenant/version"

Gem::Specification.new do |spec|
  spec.name        = "better_tenant"
  spec.version     = BetterTenant::VERSION
  spec.authors     = ["alessiobussolari"]
  spec.email       = ["alessio.bussolari@pandev.it"]
  spec.homepage    = "https://github.com/alessiobussolari/better_tenant"
  spec.summary     = "Multi-tenancy for Rails applications"
  spec.description = "BetterTenant provides transparent multi-tenancy support for Rails 8.1+ applications with schema-based and column-based strategies."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = "https://github.com/alessiobussolari/better_tenant"
  spec.metadata["changelog_uri"] = "https://github.com/alessiobussolari/better_tenant/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.0", "< 9.0"
end
