# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'procrastinator/version'

Gem::Specification.new do |spec|
   spec.name    = 'procrastinator'
   spec.version = Procrastinator::VERSION
   spec.authors = ['Robin Miller']
   spec.email   = ['robin@tenjin.ca']

   spec.summary     = %q[Delayed job queues made simple.]
   spec.description = %q[A straightforward, pure Ruby job queue that you can customize to your needs.]
   spec.homepage    = 'https://github.com/TenjinInc/procrastinator'
   spec.license     = 'MIT'

   spec.files         = `git ls-files -z`.split("\x0").reject {|f| f.match(%r{^(test|spec|features)/})}
   spec.bindir        = 'exe'
   spec.executables   = spec.files.grep(%r{^exe/}) {|f| File.basename(f)}
   spec.require_paths = ['lib']

   spec.required_ruby_version = '> 2.0'

   spec.add_development_dependency 'bundler', '~> 1.11'
   spec.add_development_dependency 'rake', '~> 10.0'
   spec.add_development_dependency 'rspec', '~> 3.0'
   spec.add_development_dependency 'timecop', '~> 0.8'
   spec.add_development_dependency 'simplecov', '~> 0.11'
   spec.add_development_dependency 'fakefs', '~> 0.10'
end
