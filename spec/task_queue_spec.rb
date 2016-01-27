require 'spec_helper'

describe Procrastinator::TaskQueue do
   describe '#initialize' do
      it 'should accept a name' do
         (1..3).each do |name|
            queue = Procrastinator::TaskQueue.new(name: name)

            expect(queue.name).to eq name
         end
      end

      it 'should accept a timeout' do
         (1..3).each do |t|

            queue = Procrastinator::TaskQueue.new(timeout: t)

            expect(queue.timeout).to eq t
         end
      end

      it 'should provide default timeout' do
         queue = Procrastinator::TaskQueue.new

         expect(queue.timeout).to eq Procrastinator::TaskQueue::DEFAULT_TIMEOUT
      end

      it 'should accept a max_attempts' do
         (1..3).each do |t|
            queue = Procrastinator::TaskQueue.new(max_attempts: t)

            expect(queue.max_attempts).to eq t
         end
      end

      it 'should provide default max_attempts' do
         queue = Procrastinator::TaskQueue.new

         expect(queue.max_attempts).to eq Procrastinator::TaskQueue::DEFAULT_MAX_ATTEMPTS
      end
   end

   it 'should have a default checking freq'
end

