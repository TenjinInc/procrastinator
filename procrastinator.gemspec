# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'procrastinator/version'

Gem::Specification.new do |spec|
   spec.name    = 'procrastinator'
   spec.version = Procrastinator::VERSION
   spec.authors = ['Robin Miller']
   spec.email   = ['robin@tenjin.ca']

   spec.summary     = 'For apps to put off work until later'
   spec.description = 'A flexible pure Ruby job queue. Tasks are reschedulable after failures.'
   spec.homepage    = 'https://github.com/TenjinInc/procrastinator'
   spec.license     = 'MIT'
   spec.metadata    = {
         'rubygems_mfa_required' => 'true'
   }

   spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
   spec.bindir        = 'exe'
   spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
   spec.require_paths = ['lib']

   spec.required_ruby_version = '>= 2.4'

   spec.add_development_dependency 'bundler', '~> 2.1'
   spec.add_development_dependency 'fakefs', '~> 1.8'
   spec.add_development_dependency 'rake', '~> 13.0'
   spec.add_development_dependency 'rspec', '~> 3.9'
   spec.add_development_dependency 'rubocop', '~> 1.12'
   spec.add_development_dependency 'rubocop-performance', '~> 1.10'
   spec.add_development_dependency 'simplecov', '~> 0.18.0'
   spec.add_development_dependency 'timecop', '~> 0.9'
end
