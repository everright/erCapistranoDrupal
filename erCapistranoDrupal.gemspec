# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'erCapistranoDrupal/version'

Gem::Specification.new do |spec|
  spec.name          = "erCapistranoDrupal"
  spec.version       = ErCapistranoDrupal::VERSION
  spec.authors       = ["everright.chen"]
  spec.email         = ["everright.chen@gmail.com"]
  spec.description   = %q{A Drupal Deploy File for Capistrano. Includes site install, database migration; support multiple subsites.}
  spec.summary       = %q{A Drupal Deploy File for Capistrano.}
  spec.homepage      = %q{http://github.com/everright/erCapistranoDrupal}
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
