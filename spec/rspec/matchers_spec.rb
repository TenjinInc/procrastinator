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

            it 'should convert string queue names to symbols' do
               store.create(queue: 'reminders', run_at: now)
               expect(store).to have_task(id: 1, queue: 'reminders')
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
            end

            it 'should match data' do
               email = 'chidi@exmaple.com'
               store.create(queue: 'reminders', run_at: Time.now, data: JSON.dump(email))
               expect(store).to have_task(data: email)
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
