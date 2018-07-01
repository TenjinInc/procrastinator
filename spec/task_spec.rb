require 'spec_helper'

module Procrastinator
   describe Task do
      let(:all_attrs) {Procrastinator::Task::KNOWN_ATTRIBUTES}

      describe '#import_task_data' do
         let(:task_class) do
            Class.new do
               include Procrastinator::Task

               def run
               end
            end
         end


         it 'should create accessors for a provided attribute' do
            task_class.import_task_data(:logger)

            task = task_class.new

            expect(task).to respond_to(:logger)
            expect(task).to respond_to(:logger=)
         end

         it 'should create accessors for all provided attributes' do
            task_class.import_task_data *all_attrs

            task = task_class.new

            all_attrs.each do |attr|
               expect(task).to respond_to(attr)
               expect(task).to respond_to("#{attr}=".to_sym)
            end
         end

         it 'should make the provided attributes available in all hook methods' do
            task_class = Class.new do
               include Procrastinator::Task

               def run
                  {
                        logger:         logger,
                        data:           data,
                        procrastinator: procrastinator,
                        context:        context
                  }
               end

               def success(result)
                  {
                        logger:         logger,
                        data:           data,
                        procrastinator: procrastinator,
                        context:        context
                  }
               end

               def fail(err)
                  {
                        logger:         logger,
                        data:           data,
                        procrastinator: procrastinator,
                        context:        context
                  }
               end

               def final_fail(err)
                  {
                        logger:         logger,
                        data:           data,
                        procrastinator: procrastinator,
                        context:        context
                  }
               end
            end

            task_class.import_task_data *all_attrs
            task = task_class.new

            logger         = double('log')
            data           = double('log')
            procrastinator = double('log')
            context        = double('log')

            task.logger         = logger
            task.data           = data
            task.procrastinator = procrastinator
            task.context        = context

            expected = {logger:         logger,
                        data:           data,
                        procrastinator: procrastinator,
                        context:        context}

            expect(task.run).to eq(expected)
            expect(task.success(nil)).to eq(expected)
            expect(task.fail(nil)).to eq(expected)
            expect(task.final_fail(nil)).to eq(expected)
         end

         it 'should complain if provided an unknown attribute' do
            known_attrs = all_attrs.collect {|a| ":#{a}"}.join(', ')

            [:bogus, :typo].each do |attr|
               err = "Unknown Procrastinator::Task attribute :#{attr}. Importable attributes are: #{known_attrs}"

               expect {task_class.import_task_data(attr)}.to raise_error(ArgumentError, err)
            end
         end
      end

      describe '#method_missing' do
         Procrastinator::Task::KNOWN_ATTRIBUTES.each do |attr|
            it "should suggest using import_task_data if #{attr} is not expected" do
               task_class = Class.new do
                  include Procrastinator::Task
               end

               task = task_class.new

               err = "To access Procrastinator::Task attribute :#{attr}, " +
                     "call import_task_data(:#{attr}) in your class definition."

               expect {task.send(attr)}.to raise_error(NameError, err)
            end
         end

         it "should should NOT raise errors if they are expected" do
            task_class = Class.new do
               include Procrastinator::Task
            end

            task_class.import_task_data(*all_attrs)

            task = task_class.new

            all_attrs.each do |attr|
               expect {task.send(attr)}.to_not raise_error
            end
         end

         it 'should do the super if it is not a known attribute' do
            task_class = Class.new do
               include Procrastinator::Task

               def run
                  send(:some_other_method)
               end
            end

            task = task_class.new

            err = "undefined method `some_other_method' for #{task}"

            expect {task.run}.to raise_error(NameError, err)
         end
      end
   end
end