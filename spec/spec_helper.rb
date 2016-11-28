
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'timecop'
require 'fakefs/safe'

require 'procrastinator'


def stub_yaml(payload)
   allow(YAML).to receive(:load) do |arg|
      payload
   end
end

# leave result+pid nil for parent thread, give int for child pid
def stub_fork(receiver, result_pid=nil)
   allow(receiver).to receive(:fork) do |&block|
      block.call
      result_pid
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