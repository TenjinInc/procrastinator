# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   module RSpec
      describe 'rspec matchers' do
         describe :have_task do
            let(:now) { Time.now }
            let(:store) { TaskStore::SimpleCommaStore.new }
            before(:each) do
               allow_any_instance_of(FakeFS::File).to receive(:flock)
            end

            it 'should be true when a metadata matches' do
               store.create(queue: 'reminders', run_at: now)
               expect(store).to have_task(id: 1)
            end

            context 'queue name' do
               it 'should match expected symbol' do
                  store.create(queue: 'reminders', run_at: now)
                  expect(store).to have_task(id: 1, queue: :reminders)
               end

               it 'should match expected string' do
                  store.create(queue: 'reminders', run_at: now)
                  expect(store).to have_task(id: 1, queue: 'reminders')
               end

               it 'should match actual string to expected symbol' do
                  store = double('store', read: [{id: 1, queue: 'reminders', run_at: now}])
                  expect(store).to have_task(id: 1, queue: :reminders)
               end

               it 'should match actual symbol to expected string' do
                  store = double('store', read: [{id: 1, queue: :reminders, run_at: now}])
                  expect(store).to have_task(id: 1, queue: 'reminders')
               end
            end

            it 'should be true when multiple metadata matches' do
               store.create(queue: 'reminders', run_at: now)
               expect(store).to have_task(id: 1, queue: :reminders, attempts: 0)
            end

            it 'should NOT match when one is unmatched' do
               store.create(queue: 'reminders', run_at: now)
               expect(store).to_not have_task(id: 2, queue: :reminders)
            end

            it 'should describe the failed match' do
               msg = 'have a task with properties id=2, queue=reminders'
               store.create(queue: 'reminders', run_at: now)
               expect do
                  expect(store).to have_task(id: 2, queue: :reminders)
               end.to raise_error ::RSpec::Expectations::ExpectationNotMetError, end_with(msg)
            end

            it 'should match other matchers' do
               store.create(queue: 'reminders', run_at: now)
               expect(store).to have_task(run_at: be_within(100).of(now))
            end

            # Time objects are precise down to subsecond values, but Procrastinator only operates with seconds precision.
            # This prevents the need for be_within for every single expectation involving a time.
            context 'time metadata conversions' do
               it 'should convert run_at' do
                  store.create(queue: 'reminders', run_at: now)
                  expect(store).to have_task(run_at: now)
               end

               it 'should convert initial_run_at' do
                  store.create(queue: 'reminders', run_at: now, initial_run_at: now)
                  expect(store).to have_task(initial_run_at: now)
               end

               it 'should convert expire_at' do
                  store.create(queue: 'reminders', run_at: now, expire_at: now)
                  expect(store).to have_task(expire_at: now)
               end

               it 'should convert last_fail_at' do
                  store.create(queue: 'reminders', run_at: now)
                  store.update(1, last_fail_at: now)
                  expect(store).to have_task(last_fail_at: now), 'last_fail_at should be converted'
               end

               it 'should round actual time fields' do
                  real_now = now
                  store    = double('fake store', read: [{queue: 'reminders', run_at: real_now, data: nil}])
                  expect(store).to have_task(run_at: real_now)
               end
            end

            it 'should match data' do
               email = 'chidi@exmaple.com'
               store.create(queue: 'reminders', run_at: Time.now, data: JSON.dump(email))
               expect(store).to have_task(data: email)
            end

            it 'should ignore nil data' do
               store = double('fake store', read: [{queue: :reminders, run_at: now, data: nil}])
               expect(store).to have_task(queue: :reminders)
            end

            it 'should match compound data matchers' do
               email = 'chidi@exmaple.com'
               store.create(queue: 'reminders', run_at: now, data: JSON.dump(first_name: 'chidi',
                                                                             last_name:  'anagonye',
                                                                             email:      email))
               expect(store).to have_task(data: include(email: email))
            end
         end
      end
   end
end
