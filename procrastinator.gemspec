# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'procrastinator/version'

Gem::Specification.new do |spec|
   spec.name    = 'procrastinator'
   spec.version = Procrastinator::VERSION
   spec.authors = ['Robin Miller']
   spec.email   = ['robin@tenjin.ca']

   spec.summary     = 'For apps that put work off until later'
   spec.description = 'A straightforward, customizable Ruby job queue with zero dependencies.'
   spec.homepage    = 'https://github.com/TenjinInc/procrastinator'
   spec.license     = 'MIT'

   spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
   spec.bindir        = 'exe'
   spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
   spec.require_paths = ['lib']

   spec.required_ruby_version = '>= 2.4'

   spec.add_development_dependency 'bundler', '~> 2.1'
   spec.add_development_dependency 'fakefs', '~> 0.10'
   spec.add_development_dependency 'rake', '~> 12.3'
   spec.add_development_dependency 'rspec', '~> 3.0'
   spec.add_development_dependency 'rubocop', '~> 0.88'
   spec.add_development_dependency 'rubocop-performance', '~> 1.7.1'
   spec.add_development_dependency 'simplecov', '~> 0.16.1'
   spec.add_development_dependency 'timecop', '~> 0.9'
end
