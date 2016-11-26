$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'timecop'

require 'procrastinator'

def stub_yaml(payload)
   allow(YAML).to receive(:load) do |arg|
      payload
   end
end

def stub_fork(receiver)
   allow(receiver).to receive(:fork) do |&block|
      block.call
      nil
   end
end

class GoodTask
   def initialize

   end

   def run

   end

   def success(env)

   end

   def fail(env)
   end

   def final_fail(env)

   end
end