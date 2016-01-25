# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'procrastinator/version'

Gem::Specification.new do |spec|
  spec.name          = "procrastinator"
  spec.version       = Procrastinator::VERSION
  spec.authors       = ["Robin Miller"]
  spec.email         = ["robin@tenjin.ca"]

  spec.summary       = %q{Simple generalized job queues.}
  spec.description   = %q{A strightforward job queue that is not dependent on Rails or any particular database or persistence mechanism.}
  spec.homepage      = "https://github.com/TenjinInc/procrastinator"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
