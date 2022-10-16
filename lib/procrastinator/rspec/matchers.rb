# frozen_string_literal: true

require 'rspec/expectations'

# Determines if the given task store has a task that matches the expectation hash
RSpec::Matchers.define :have_task do |expected_task|
   match do |task_store|
      expected_task[:queue] = expected_task[:queue].to_sym if expected_task[:queue]

      Procrastinator::Task::TIME_FIELDS.each do |time_field|
         if expected_task[time_field]&.respond_to?(:to_i)
            expected_task[time_field] = Time.at(expected_task[time_field].to_i)
         end
      end

      expected = a_hash_including(expected_task)

      actual_tasks = task_store.read.collect do |task|
         task_hash = task.to_h
         unless task_hash[:data].nil? || task_hash[:data].empty?
            task_hash[:data] = JSON.parse(task_hash[:data], symbolize_names: true)
         end
         task_hash[:queue] = task_hash[:queue].to_sym if task_hash[:queue]
         Procrastinator::Task::TIME_FIELDS.each do |time_field|
            task_hash[time_field] = Time.at(task_hash[time_field].to_i) if task_hash[time_field]&.respond_to?(:to_i)
         end

         task_hash
      end

      values_match? a_collection_including(expected), actual_tasks
   end

   description do
      "have a task with properties #{ expected_task.collect { |k, v| "#{ k }=#{ v }" }.join(', ') }"
   end
end
