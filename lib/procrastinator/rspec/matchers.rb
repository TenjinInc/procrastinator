# frozen_string_literal: true

require 'rspec/expectations'

# Determines if the given task store has a task that matches the expectation hash
RSpec::Matchers.define :have_task do |expected_task|
   match do |task_store|
      task_store.read.any? do |task|
         task_hash        = task.to_h
         task_hash[:data] = JSON.parse(task_hash[:data], symbolize_names: true) unless task_hash[:data].empty?

         expected_task.all? do |field, expected_value|
            expected_value = case field
                             when :queue
                                expected_value.to_sym
                             when :run_at, :initial_run_at, :expire_at, :last_fail_at
                                Time.at(expected_value.to_i)
                             else
                                expected_value
                             end

            values_match? expected_value, task_hash[field]
         end
      end
   end

   description do
      "have a task with properties #{ expected_task.collect { |k, v| "#{ k }=#{ v }" }.join(', ') }"
   end
end
