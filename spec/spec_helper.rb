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