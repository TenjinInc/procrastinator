# Procrastinator
Procrastinator is a pure ruby job scheduling gem to allow your app to put off work for later. 
Tasks are scheduled in queues and those queues are monitored by separate worker subprocesses. 
Once the scheduled time arrives, the queue worker performs that task. 

If the task fails to complete or takes too long, it delays it and tries again later.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'procrastinator'
```

And then run:

    bundle install

## Quick Start
Setup a procrastination environment:

```ruby
procrastinator = Procrastinator.setup do |env|
   env.load_with do
      # eg. connect to a database, etc 
      # then provide a class that does task I/O
      MyTaskLoader.new('my-tasks.csv')
   end
   
   env.define_queue(:greeting, SendWelcomeEmail)
   env.define_queue(:thumbnail, GenerateThumbnail, timeout: 60)
   env.define_queue(:birthday, SendBirthdayEmail, max_attempts: 3)
end
```

And then get your lazy on:

```ruby
procrastinator.delay(:greeting, data: 'bob@example.com')

procrastinator.delay(:thumbnail, data: {file: 'full_image.png', width: 100, height: 100})

procrastinator.delay(:send_birthday_email, run_at: Time.now + 3600, data: {user_id: 5})
```

Read on for more details:

1. [Configuration](#configuration)
   1. [Task Loader](#task-loader-load_with)
   1. [Task Context](#task-context-provide_context)
   1. [Defining Queues](#defining-queues-define_queue)
1. [Scheduling Tasks](#scheduling-tasks)
1. [Tasks](#tasks)
1. [Logging](#logging)

## Configuration
Procrastinator.setup allows you to define a task loader, a task context, and available queues.

```ruby
Procrastinator.setup do |env|
   # ... call methods on env to set configurations
end
```

It then spins off a sub process to work on each queue and returns the configured environment,
and you use that environment to `#delay` tasks.   

### Task Loader: `#load_with`
Your task loader is a [strategy](https://en.wikipedia.org/wiki/Strategy_pattern) pattern object
that knows how to read and write tasks in your data storage (eg. file, database, etc).

In setup, the environment's `#load_with` method expects a block that constructs and returns an instance of
your persistence strategy class. **That block will be run in each sub-process**, which allows for 
per-process resource management (eg. providing separate database connections).

Example:
```ruby
procrastinator = Procrastinator.setup do |env|
   env.load_with do
      connection = SomeDatabaseLibrary.connect('my_app_development')
      MyTaskLoader.new(connection)
   end
   
   # .. other setup stuff ...
end
```

Your task loader class is required to implement *all* of the following four methods: 

1. `#read_tasks(queue_name)`

   Returns a list of hashes from your datastore for the specified queue name. 
   Each hash must contain the properties listed in [Task Data](#task-data) below.
     
2. `#create_task(data)`

   Creates a task in your datastore. Receives a hash with [Task Data](#task-data) keys: 
   `:queue`, `:run_at`, `:initial_run_at`, `:expire_at`, and `:task`.
    
3. `#update_task(new_data)`
 
   Saves the provided full [Task Data](#task-data) hash to your datastore.
   
4. `#delete_task(id)`
 
   Deletes the task with the given identifier in your datastore.

<!-- This paragraph is here to allow people to google for the error keyword -->
If your task loader is missing any of the above methods, 
Procrastinator will explode with a `MalformedPersisterError`  and you will be sad. 

#### Task Data
These are the data fields for each individual scheduled task. If you have a database, this is basically your table schema. 

|  Hash Key         | Type   | Description                                                                             |
|-------------------|--------| ----------------------------------------------------------------------------------------|
| `:id`             | int    | Unique identifier for this exact task                                                   |
| `:queue`          | symbol | Name of the queue the task is inside                                                    | 
| `:run_at`         | int    | Unix timestamp of when to next attempt running the task                                 |
| `:initial_run_at` | int    | Unix timestamp of the originally requested run                                          |
| `:expire_at`      | int    | Unix timestamp of when to permanently fail the task because it is too late to be useful |
| `:attempts`       | int    | Number of times the task has tried to run; this should only be > 0 if the task fails    |
| `:last_fail_at`   | int    | Unix timestamp of when the most recent failure happened                                 |
| `:last_error`     | string | Error message + bracktrace of the most recent failure. May be very long.                |
| `:data`           | string | Data to be passed into the task initializer. Keep to simple data types; serialized as YAML.|

The `:data` is serialized with YAML.dump.

Notice that the times are all given as unix epoch timestamps. This is to avoid any confusion with timezones, 
and it is recommended that you store times in this manner for the same reason. 

### Task Context: `#provide_context`
Similar to `#load_with`, `#provide_context` takes a block that is executed on the sub process and the result is passed 
into each of your task's hooks as the first parameter. 

This is useful for things like creating other database connections or passing in shared state. 

```ruby
Procrastinator.setup do |env|
   # .. other setup stuff ...
 
   env.provide_context do 
      {message: "This hash will be passed into your task's methods"}
   end
end
```

### Defining Queues: `#define_queue`
In the setup block, you can call `#define_queue` on the environment: 

```ruby
Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue(:greeting, SendWelcomeEmail)
end
```

The first two parameters are the queue name symbol and the task class to run on that queue. You can also 
provide these keyword arguments:

 * `:timeout`
 
   Duration (seconds) after which tasks in this queue should fail for taking too long.
    
 * `:max_attempts` 
 
   Maximum number of attempts for tasks in this queue. Once attempts is meets or exceeds `max_attempts`, the task will 
   be permanently failed.
    
 * `:update_period`
  
   Delay, in seconds, between reloads of all tasks from the task loader.
   
 * `:max_tasks`
 
   The maximum number of tasks to run concurrently within a queue worker process.


```ruby 
# all defaults set explicitly:
env.define_queue(:queue_name, YourTaskClass, timeout: 3600, max_attempts: 20, update_period: 10, max_tasks: 10)
```

### Other Setup Methods
Each queue is worked in a separate process and you can call `#prefix_process` and provide a subprocess prefix.

<!-- , and each process multi-threaded to handle more than one task at a time. 
    This should help prevent a single task from clogging up the whole queue -->

```ruby
procrastinator = Procrastinator.setup do |env|
   # ... other setup stuff ...
   
   env.prefix_processes('myapp')
end
```

The sub-processes checks that the parent process is still alive every 5 seconds. 
If there is no process with the parent's PID, the sub-process will self-exit. 

## Scheduling Tasks
To schedule tasks, just call `#delay` on the environment returned from `Procrastinator.setup`: 

```ruby
procrastinator = Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue(:reminder, EmailReminder)
   env.define_queue(:thumbnail, CreateThumbnail)
end

# Provide the queue name and any data you want passed in
procrastinator.delay(:reminder, data: 'bob@example.com')
```

If you have only one queue, you can omit the queue name: 

```ruby
procrastinator = Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue(:reminder, EmailReminder)
end

procrastinator.delay(data: 'bob@example.com')
```

### Controlling the Timing
You can set when the particular task is to be run and/or when it should expire. Be aware that the task is not guaranteed 
to run at a precise time; the only promise is that the task will be attempted *after* `run_at` and before `expire_at`.

```ruby
# runs on or after 1 January 3000
procrastinator.delay(:greeting, run_at: Time.new(3000, 1, 1), data: 'philip_j_fry@example.com')

# run_at defaults to right now:
procrastinator.delay(:thumbnail, run_at: Time.now, data: 'shut_up_and_take_my_money.gif')
```

You can also set an `expire_at` deadline. If the task has not been run before `expire_at` is passed, then it will be 
final-failed the next time it would be attempted.
Setting `expire_at` to `nil` means it will never expire (but may still fail permanently if, 
say, `max_attempts` is reached).

```ruby
# will not run at or after 
procrastinator.delay(:happy_birthday, expire_at: Time.new(2018, 03, 17, 12, 00, '-06:00'),  data: 'contact@tenjin.ca'))

# expire_at defaults to nil:
procrastinator.delay(:greeting, expire_at: nil, data: 'bob@example.com')
```

## Tasks
Your task class is what actually gets run on the task queue. They will look something like this: 


```ruby
class MyTask
   # Receives the data stored in the call to #delay
   def initialize(data)
      # ... assign to instance variables ...
   end
   
   # Performs the core work of the task. 
   def run(context, logger)
      # ... perform your task ...
   end
   
   
   # ========================================
   #             OPTIONAL HOOKS
   # ========================================
   #
   # You can always omit any of the methods below. Only #run is mandatory.
   #
   
   # Called after the task has completed successfully. 
   # Receives the result of #run.
   def success(context, logger, run_result)
      # ...
   end
   
   # Called after #run raises a StandardError or subclass.
   def fail(context, logger, error)
      # ...
   end
   
   # Called after either is true: 
   #   1. the time reported by Time.now is past the task's expire_at time.
   #   2. the task has failed and the number of attempts is equal to or greater than the queue's `max_attempts`. 
   #      In this case, #fail will not be executed, only #final_fail. 
   #
   # When called, the task will be marked to never be run again.
   def final_fail(context, logger, error)
      # ...
   end
end
```


It **must provide** a `#run` method, but `#success`, `#fail`, and `#final_fail` are optional. 
The initializer is required if you provide the `:data` argument when you schedule it with `#delay`. 

See the [Task Context](#task-context-provide_context) and [Logging](#logging) sections for explanations of 
the `context` and `logger` parameters.

### Retries
Failed tasks have their `run_at` rescheduled on an increasing delay (in seconds) according to this formula: 
    
> 30 + (number_of_attempts)<sup>4</sup>

Situations that call `#fail` or `#final_fail` will cause the error timestamp and reason to be stored in `:last_fail_at` 
and `:last_error`.

### TDD With Procrastinator
Procrastinator uses multi-threading and multi-processing internally, which is a nightmare for automated testing. 
Test Mode will disable all of that and rely on your tests to tell it when to act. 

Set `Procrastinator.test_mode = true` before setup, or call `#enable_test_mode` on 
the procrastination environment:

```ruby
# all further calls to `Procrastinator.setup` will produce a procrastination environment where Test Mode is enabled
Procrastinator.test_mode = true
 
# or you can also enable it in the setup
env = Procrastinator.setup do |env|
   env.enable_test_mode
    
   # ... other settings...
end
```

Then in your tests, tell the procrastinator environment to work off one item: 

```
# execute one task on all queues
env.act

# or provide queue names to execute one task on those specific queues
env.act(:cleanup, :email)
```

## Logging
Each queue worker writes its own log, named after its queue (eg. `log/welcome-queue-worker.log`), in
the defined log directory using the Ruby 
[Logger class](https://ruby-doc.org/stdlib-2.5.1/libdoc/logger/rdoc/Logger.html).

```ruby
procrastinator = Procrastinator.setup do |env|
   # ... other setup stuff ... 

   # you can set custom log directory and level:
   env.log_in('/var/log/myapp/')
   env.log_at_level(Logger::DEBUG)
   
   # these are the default values:
   env.log_in('log/') # relative to the running directory
   env.log_at_level(Logger::INFO)
   
   # disable logging entirely:
   env.log_in(nil)
end
```

The logger is passed into each of the hooks (`#run`, `#success`, etc) in your task class as the second parameter:
```ruby
class MyTask
   def run(context, logger)
      logger.info('This task was run.')
   end
end
```

**Default Log Messages**

|event               |level  |
|--------------------|-------|
|process started     | INFO  |
|parent process gone | ERROR |
|#success called     | DEBUG |
|#fail called        | DEBUG |
|#final_fail called  | DEBUG |

## Contributing
Bug reports and pull requests are welcome on GitHub at 
[https://github.com/TenjinInc/procrastinator](https://github.com/TenjinInc/procrastinator).
 
This project is intended to be a friendly space for collaboration, and contributors are expected to adhere to the 
[Contributor Covenant](http://contributor-covenant.org) code of conduct.

Play nice.

### Developers
After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can 
also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the 
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, 
push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
