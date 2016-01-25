require 'spec_helper'

describe Procrastinator do
   it 'should have a version number' do
      expect(Procrastinator::VERSION).not_to be nil
   end

   describe '#delay' do
      it 'should record a task'

      it 'should complain when the given queue is not registered'
   end

   describe '#spawn_worker' do
      it 'should fork a worker process for the given queue' # tODO: test that it forks a process, and names it
      it 'should tell the worker process to work' # TODO and that the subprocess creates a worker and #works
      it 'should kill children on natural exit'
      it 'should kill children on receiving a termination signal' #TODO: SIGKILL, SIGTERM, SIGQUIT, SIGINT
      # TODO: test for any zombie processes

      after(:each) do
         # tODO: how do we figure out how to find which ones are written by the tests?
         # tODO: kill any zombie processes left by the tests
      end
   end

   describe '#work' do
      it 'should run standalone'
   end
end

