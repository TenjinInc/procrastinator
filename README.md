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

## Big Picture
If you have tasks like this:

```ruby
class SendWelcomeEmail
   def run
      # ... email stuff ...
   end
end
```

Setup a procrastination environment:
```ruby
scheduler = Procrastinator.setup do |env|
   env.define_queue :greeting, SendWelcomeEmail
   env.define_queue :thumbnail, GenerateThumbnail, timeout: 60
   env.define_queue :birthday, SendBirthdayEmail, max_attempts: 3
   
   env.load_with MyTaskLoader.new('my-tasks.csv')
end
```

And then get your lazy on:

```ruby
scheduler.delay(:greeting, data: 'bob@example.com')

scheduler.delay(:thumbnail, data: {file: 'full_image.png', width: 100, height: 100})

scheduler.delay(:send_birthday_email, run_at: Time.now + 3600, data: {user_id: 5})
```

##Contents
  * [Setup](#setup)
    + [Defining Queues: `#define_queue`](#defining-queues----define-queue-)
    + [The Task Loader: `#load_with`](#the-task-loader----load-with-)
      - [Task Data](#task-data)
    + [The Task Context: `#provide_context`](#the-task-context----provide-context-)
    + [The Subprocess Hook: `#each_process`](#the-subprocess-hook----each-process-)
    + [Naming Processes: `#process_prefix`](#naming-processes----process-prefix-)
  * [Tasks](#tasks)
    + [Accessing Task Attributes](#accessing-task-attributes)
    + [Retries](#retries)
  * [Scheduling Tasks](#scheduling-tasks)
    + [Providing Data](#providing-data)
    + [Controlling Timing](#controlling-timing)
  * [Test Mode](#test-mode)
  * [Errors & Logging](#errors---logging)

## Setup
Procrastinator.setup allows you to define a task loader, a task context, and available queues.

```ruby
Procrastinator.setup do |env|
   # ... call methods on env to set configurations
end
```

It then spins off a sub process to work on each queue and returns the configured environment,
and you use that environment to `#delay` tasks.   

The sub-processes checks that the parent process is still alive every 5 seconds. 
If there is no process with the parent's PID, the sub-process will self-exit. 

### Defining Queues: `#define_queue`
In the setup block, you can call `#define_queue` on the environment: 

```ruby
Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue :greeting, SendWelcomeEmail
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
env.define_queue :queue_name, YourTaskClass, timeout: 3600, max_attempts: 20, update_period: 10, max_tasks: 10
```

### The Task Loader: `#load_with`
Your task loader is a [strategy](https://en.wikipedia.org/wiki/Strategy_pattern) pattern object
that knows how to read and write tasks in your data storage (eg. file, database, etc).

In setup, the environment's `#load_with` method expects an instance of this class. 

```ruby
loader = MyTaskLoader.new('tasks.csv')

scheduler = Procrastinator.setup do |env|
   env.load_with loader
   
   # .. other setup stuff ...
end
```

If you need per-process resource management (eg. independent database connections), put the relevant code inside 
the `#each_process` block.

```ruby
connection = SomeDatabaseLibrary.connect('my_app_development')

scheduler = Procrastinator.setup do |env|
   env.load_with MyTaskLoader.new(connection)
   
   env.each_process do
      # make a fresh connection
      connection.reconnect
      env.load_with MyTaskLoader.new(connection)
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
| `:run_at`         | int    | Unix timestamp of when to next attempt running the task.                                |
| `:initial_run_at` | int    | Unix timestamp of the originally requested run                                          |
| `:expire_at`      | int    | Unix timestamp of when to permanently fail the task because it is too late to be useful |
| `:attempts`       | int    | Number of times the task has tried to run; this should only be > 0 if the task fails    |
| `:last_fail_at`   | int    | Unix timestamp of when the most recent failure happened                                 |
| `:last_error`     | string | Error message + bracktrace of the most recent failure. May be very long.                |
| `:data`           | string | Data to be passed into the task initializer. Keep to simple data types; serialized as YAML.|

The `:data` is serialized with YAML.dump.

If `:run_at` is `nil`, that indicates that it is permanently failed and will never run, either due to expiry or too many failures. 

Notice that the times are all given as unix epoch timestamps. This is to avoid any confusion with timezones, 
and it is recommended that you store times in this manner for the same reason. 

### The Task Context: `#provide_context`
Whatever you give to `#provide_context` will be made available to your Task through the task attribute `:context`. 

This can be useful for things like app containers, but you can use it for whatever you like.  

```ruby
Procrastinator.setup do |env|
   # .. other setup stuff ...
 
   env.provide_context {message: "This hash will be passed into your task's methods"}
end

# ... and in your task ...
class MyTask
   include Procrastinator::Task
   
   task_attr :context
   
   def run
      puts "My context is: #{context}"
   end
end
```

### The Subprocess Hook: `#each_process`
In the setup block, you specify which actions to take specifically on the subprocesses with `#each_process`. Whatever
is in the block will be run after the process is forked and before the queue worker starts. 

```ruby
Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.each_process do 
      # create process-specific resources here, like database connections 
      # (the parent process's connection could disappear, because they're asychnronous)
      connection = SomeDatabase.connect('bob@mainframe/my_database')
      
      # these two are the configuration methods you're most likely to use in #each_process
      config.provide_context MyApp.build_task_package
      config.load_with MyDatabase.new(connection)
   end
end
```

NB: That block is **not run in Test Mode**. 

### Naming Processes: `#process_prefix`
Each queue subprocess is named after the queue it's working on, 
eg. `greeting-queue-worker` or `thumbnails-queue-worker`.

If you're running multiple apps on the same machine, then you may want to distinguish which app the queue worker 
was spawned for. You can call `#prefix_process` and provide a string that will be added to the front of the prcoess 
names.

```ruby
scheduler = Procrastinator.setup do |env|
   # ... other setup stuff ...
   
   env.prefix_processes 'myapp'
end
```

## Tasks
Your task class is what actually gets run on the task queue. They will look something like this: 


```ruby
class MyTask
   include Procrastinator::Task
   
   # Give any of these symbols to task_attr and they will become available as methods
   # task_attr :data, :logger, :context, :scheduler
   
   # Performs the core work of the task. 
   def run
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
   def success(run_result)
      # ...
   end
   
   # Called after #run raises any StandardError (or subclass).
   # Receives the raised error.
   def fail(error)
      # ...
   end
   
   # Called after either is true: 
   #   1. the time reported by Time.now is past the task's expire_at time.
   #   2. the task has failed and the number of attempts is equal to or greater than the queue's `max_attempts`. 
   #      In this case, #fail will not be executed, only #final_fail. 
   #
   # When called, the task will be marked to never be run again.
   # Receives the raised error.
   def final_fail(error)
      # ...
   end
end
```

It **must provide** a `#run` method, but `#success`, `#fail`, and `#final_fail` are optional. 

### Accessing Task Attributes
Include `Procrastinator::Task` in your task class and then use `task_attr` to register which task attributes your 
task wants access to. 

```ruby
class MyTask
   include Procrastinator::Task
   
   # declare the task attributes you care about by calling task_attr. 
   # You can use any of these symbols: 
   #             :data, :logger, :context, :scheduler
   task_attr :data, :logger
   
   def run
      # the attributes listed in task_attr become methods like attr_accessor
      logger.info("The data for this task is #{data}")
   end
end   
```

 * `:data`
   This is the data that you provided in the call to `#delay`. Any task that registers `:data` as a task 
   attribute will require data be passed to `#delay`.
   See [Task Data](#task-data) for more.
   
 * `:context`
  
   The context you've provided in your setup. See [Task Context](#task-context-provide_context) for more.
 
 * `:logger`
    
   The queue's Logger object. See [Logging](#logging) for more.
    
 * `:scheduler`
 
   A scheduler object that you can use to schedule new tasks (eg. with `#delay`).


### Retries
Failed tasks have their `run_at` rescheduled on an increasing delay (in seconds) according to this formula: 

> 30 + (number_of_attempts)<sup>4</sup>

Situations that call `#fail` or `#final_fail` will cause the error timestamp and reason to be stored in `:last_fail_at` 
and `:last_error`.


## Scheduling Tasks
To schedule tasks, just call `#delay` on the environment returned from `Procrastinator.setup`: 

```ruby
scheduler = Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue :reminder, EmailReminder
   env.define_queue :thumbnail, CreateThumbnail
end

# Provide the queue name and any data you want passed in
scheduler.delay(:reminder, data: 'bob@example.com')
``` 

If you have only one queue, you can omit the queue name: 

```ruby
scheduler = Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue :reminder, EmailReminder
end

scheduler.delay(data: 'bob@example.com')
```

### Providing Data
Most tasks need some additional information to complete their work, like id numbers, 

The `:data` parameter is serialized to string as YAML, so it's better to keep it as simple as possible. For example, if 
you have a database instead of passing in a complex Ruby object, pass in just the primary key and reload it in the 
task's `#run`. This will require less space in your database and avoids obsolete or duplicated information.    

### Controlling Timing
You can set when the particular task is to be run and/or when it should expire. Be aware that the task is not guaranteed 
to run at a precise time; the only promise is that the task will be attempted *after* `run_at` and before `expire_at`.

```ruby
# runs on or after 1 January 3000
scheduler.delay(:greeting, run_at: Time.new(3000, 1, 1), data: 'philip_j_fry@example.com')

# run_at defaults to right now:
scheduler.delay(:thumbnail, run_at: Time.now, data: 'shut_up_and_take_my_money.gif')
```

You can also set an `expire_at` deadline. If the task has not been run before `expire_at` is passed, then it will be 
final-failed the next time it would be attempted.
Setting `expire_at` to `nil` means it will never expire (but may still fail permanently if, 
say, `max_attempts` is reached).

```ruby
# will not run at or after 
scheduler.delay(:happy_birthday, expire_at: Time.new(2018, 03, 17, 12, 00, '-06:00'),  data: 'contact@tenjin.ca'))

# expire_at defaults to nil:
scheduler.delay(:greeting, expire_at: nil, data: 'bob@example.com')
```

### Rescheduling
Call `#reschedule` with the queue name and some identifying 
information, and then calling #to on that to provide the new time.

```ruby
scheduler = Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue :reminder, EmailReminder
end

scheduler.delay(:reminder, run_at: Time.parse('June 1'), data: 'bob@example.com')

# we can reschedule the task made above 
scheduler.reschedule(:reminder, data: 'bob@example.com').to(run_at: Time.parse('June 20 12:00'))

# we can also change the expiry time
scheduler.reschedule(:reminder, data: 'bob@example.com').to(expire_at: Time.parse('June 23 12:00'))

# or both
scheduler.reschedule(:reminder, data: 'bob@example.com').to(run_at:    Time.parse('June 20 12:00'), 
                                                            expire_at: Time.parse('June 23 12:00'))
```

Rescheduling updates the task's `:run_at` and `:initial_run_at` to a new value, if provided and/or 
`:expire_at` to a new value if provided. A `RuntimeError` is raised if the resulting runtime is after the expiry. 

It also resets `:attempts` to `0` and clears both `:last_error` and `:last_error_at` to `nil`.

Rescheduling will not change `:id`, `:queue` or `:data`.

## Test Mode
Procrastinator uses multi-threading and multi-processing internally, which is a nightmare for automated testing. 
Test Mode will disable all of that and rely on your tests to tell it when to act. 

Set `Procrastinator.test_mode = true` before setup, or call `#enable_test_mode` on 
the procrastination environment:

```ruby
# all further calls to `Procrastinator.setup` will produce a procrastination environment where Test Mode is enabled
Procrastinator.test_mode = true
 
# or you can also enable it in the setup
scheduler = Procrastinator.setup do |env|
   env.enable_test_mode
    
   # ... other settings...
end
```

Then in your tests, tell the procrastinator environment to work off one item: 

```
# execute one task on all queues
env.act

# or provide queue names to execute one task on those specific queues
scheduler.act(:cleanup, :email)
```

## Errors & Logging
Errors that trigger #fail or #final_fail are saved in the task persistence (database, file, etc) under `last_error` and 
`last_error_at`.

Each queue worker also writes its own log using the Ruby 
[Logger class](https://ruby-doc.org/stdlib-2.5.1/libdoc/logger/rdoc/Logger.html).
The log files are named after its queue process name (eg. `log/welcome-queue-worker.log`) and
they are saved in the log directory defined in setup. 

```ruby
scheduler = Procrastinator.setup do |env|
   # ... other setup stuff ... 

   # you can set custom log directory and level:
   env.log_inside '/var/log/myapp/'
   env.log_at_level Logger::DEBUG
   
   # these are the defaults:
   env.log_inside 'log/' # relative to the running directory
   env.log_at_level Logger::INFO
   
   # use nil to disable logging entirely:
   env.log_inside nil
end
```

The logger can be accessed in your tasks by including Procrastinator::Task in your task class and then calling
`task_attr :logger`. 

```ruby
class MyTask
   include Procrastinator::Task
   
   task_attr :logger

   def run
      logger.info('This task got run. Hooray!')
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
