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

   spec.required_ruby_version = '>= 3.0'
end
