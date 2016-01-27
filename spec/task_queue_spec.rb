require 'spec_helper'

describe Procrastinator::TaskQueue do
   describe '#initialize' do
      it 'should require a name' do
         expect { Procrastinator::TaskQueue.new }.to raise_error(ArgumentError)
      end

      it 'should store name as symbol' do
         [:email, :cleanup, 'a name'].each do |name|
            queue = Procrastinator::TaskQueue.new(name: name)

            expect(queue.name).to eq name.to_s.gsub(/\s/, '_').to_sym
         end
      end

      it 'should require the name not be nil' do
         expect { Procrastinator::TaskQueue.new(name: nil) }.to raise_error(ArgumentError, 'Queue name may not be nil')
      end

      it 'should accept a timeout' do
         (1..3).each do |t|

            queue = Procrastinator::TaskQueue.new(name: :queue, timeout: t)

            expect(queue.timeout).to eq t
         end
      end

      it 'should provide default timeout' do
         queue = Procrastinator::TaskQueue.new(name: :queue)

         expect(queue.timeout).to eq Procrastinator::TaskQueue::DEFAULT_TIMEOUT
      end

      it 'should accept a max_attempts' do
         (1..3).each do |t|
            queue = Procrastinator::TaskQueue.new(name: :queue, max_attempts: t)

            expect(queue.max_attempts).to eq t
         end
      end

      it 'should provide default max_attempts' do
         queue = Procrastinator::TaskQueue.new(name: :queue)

         expect(queue.max_attempts).to eq Procrastinator::TaskQueue::DEFAULT_MAX_ATTEMPTS
      end
   end

   it 'should have a default checking freq'
end

