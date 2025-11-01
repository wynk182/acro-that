# frozen_string_literal: true

require_relative 'lib/acro_that/version'

Gem::Specification.new do |spec|
  spec.name          = "acro_that"
  spec.version       = AcroThat::VERSION
  spec.authors       = ["Michael Wynkoop"]
  # spec.email         = ["michaelwynkoop@corporatetools.com"]
  spec.email         = ["wynk182@gmail.com"]

  spec.summary       = "Pure Ruby PDF AcroForm editing library"
  spec.description   = "A minimal pure Ruby library for parsing and editing PDF AcroForm fields using only stdlib"
  spec.homepage      = "https://github.com/wynk182/acro_that"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/wynk182/acro_that"
  spec.metadata["changelog_uri"] = "https://github.com/wynk182/acro_that/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "chunky_png", "~> 1.4"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rspec", "~> 2.20"
end
