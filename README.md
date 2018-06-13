# Procrastinator

Procrastinator is a pure ruby job scheduling gem to allow your app to put off work for later. 
Tasks are scheduled in queues and those queues are monitored by separate worker subprocesses. 
Once the scheduled time arrives, the queue worker performs that task. 

If the task fails to complete or takes too long, it delays it until even later.  

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'procrastinator'
```

And then run:

    bundle install

## Usage
Setup a procrastination environment:

```ruby
procrastinator = Procrastinator.setup do |env|
   env.load_with do
      # eg. read a file, database, cloud service, whatever you need. 
      MyTaskLoader.new('my-tasks.csv')
   end
   
   env.define_queue(:email)
   env.define_queue(:cleanup, max_attempts: 3)
end
```

And then get your lazy on:

```ruby
procrastinator.delay(queue: :email, task: EmailGreeting.new('bob@example.com'))
procrastinator.delay(queue: :cleanup, run_at: Time.now + 3600, task: ClearTempData.new)
```

Read on for more details on each step. 

---------------------------------------

### Setup Phase
Procrastinator.setup allows you to define a task loader, a task context, and available queues.

```ruby
Procrastinator.setup do |env|
   # ... call methods on env to set configurations
end
```

It then spins off a sub process to work on each queue and returns the configured environment.  

#### Task Loader: `#load_with`
Your task loader is the intermediary between Procrastinator and your data storage (eg. file, database, etc).
This is a [strategy](https://en.wikipedia.org/wiki/Strategy_pattern) pattern object used for task persistence - 
loading and saving task data.

The environment's `#load_with` method expects a block that constructs and returns an instance of
your persistence strategy class. That block will be run in each sub-process, which allows for 
resource management (eg. providing separate database connections).

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

<!-- This graph is here to allow people to google for the error keyword -->
If your task loader is missing any of the above methods, 
Procrastinator will explode with a `MalformedPersisterError`  and you will be sad. 

##### Task Data

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
| `:task`           | string | YAML-dumped ruby object definition of the task.                                         |

Notice that the times are all given as unix epoch timestamps. This is to avoid any confusion with timezones, 
and it is recommended that you store times in this manner for the same reason. 

#### Task Context: `#task_context`
Similar to `#load_with`, `#task_context` takes a block that is executed on the sub process and the result is passed 
into each of your task's hooks as the first parameter.  

```ruby
Procrastinator.setup do |env|
   # .. other setup stuff ...
 
   env.task_context do 
      {message: "This hash will be passed into your task's methods"}
   end
end
```

#### Defining Queues: `#define_queue`
In the setup block, you can call `#define_queue` on the environment: 

```ruby
Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue(:email)
end
```

Optionally, you can provide a queue name symbol and these keyword arguments: 

 * `:timeout`
 
   Time, in seconds, after which it should fail tasks in this queue for taking too long to execute.
    
 * `:max_attempts` 
 
   Maximum number of attempts for tasks in this queue. If attempts is >= max_attempts, the task will be final_failed 
   and marked to never run again
    
 * `:update_period`
  
   Delay, in seconds, between refreshing the task list from the task loader.
   
 * `:max_tasks`
 
   The maximum number of tasks to run concurrently within a queue worker. 


```ruby 
Procrastinator.setup do |env|
   # ... other setup stuff ...
   
   # all defaults set explicitly:
   env.define_queue(:email, timeout: 3600, max_attempts: 20, update_period: 10, max_tasks: 10)
end
```

#### Other Setup Methods
Each queue is worked in a separate process and you can call `#process_prefix` and provide a subprocess prefix.  

<!-- , and each process multi-threaded to handle more than one task at a time. 
    This should help prevent a single task from clogging up the whole queue -->

```ruby
procrastinator = Procrastinator.setup do |env|
   # ... other setup stuff ...
   
   env.process_prefix('myapp')
end
```

The sub-processes checks that the parent process is still alive every 5 seconds. 
If there is no process with the parent's PID, the sub-process will self-exit. 

---------------------------------------

### Scheduling Tasks
Procrastinator will let you be lazy: 

```ruby
procrastinator = Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue(:email)
end

procrastinator.delay(task: EmailReminder.new('bob@example.com'))
```

... unless there are multiple queues defined. Then you must provide a queue name with your task:

```ruby
procrastinator = Procrastinator.setup do |env|
   # ... other setup stuff ...

   env.define_queue(:email)
   env.define_queue(:cleanup)
end

procrastinator.delay(:email, task: EmailReminder.new('bob@example.com'))
```

You can set when the particular task is to be run and/or when it should expire. Be aware that the task is not guaranteed 
to run at a precise time; the only promise is that the task will get run some time after `run_at`, unless it's after `expire_at`. 

```ruby
procrastinator = Procrastinator.setup(task_persister) do |env|
   # ... other setup stuff ...

   env.define_queue(:email)
end

# run on or after 1 January 3000
procrastinator.delay(run_at: Time.new(3000, 1, 1), task: EmailGreeting.new('philip_j_fry@example.com'))

# explicitly setting default run_at
procrastinator.delay(run_at: Time.now, task: EmailReminder.new('bob@example.com'))
```

You can also set an `expire_at` deadline on when to run a task. If the task has not been run before `expire_at` is passed, then it will be final-failed the next time it is attempted. Setting `expire_at` to `nil` will mean it will never expire (but may still fail permanently if, say, `max_attempts` is reached).

```ruby
procrastinator = Procrastinator.setup(task_persister) do |env|
   # ... other setup stuff ...

   env.define_queue(:email)
end

procrastinator.delay(expire_at: , task: EmailGreeting.new('bob@example.com'))

# explicitly setting default
procrastinator.delay(expire_at: nil, task: EmailGreeting.new('bob@example.com'))
```

#### Task Definition
Like the persister provided to `.setup`, your task is a strategy object that fills in the details of what to do. For this, 
your task **must provide** a `#run` method:

 * `#run` - Performs the core work of the task.

You may also optionally provide these hook methods, which are run during different points in the process:

 * `#success(logger)` - run after the task has completed successfully 
 * `#fail(logger, error)` - run after the task has failed due to `#run` producing a `StandardError` or subclass.
 * `#final_fail(logger, error)` - run after the task has failed for the last time because either:
    1. the number of attempts is >= the `max_attempts` defined for the queue; or
    2. the time reported by `Time.now` is past the task's `expire_at` time.

If a task reaches `#final_fail` it will be marked to never be run again.

***Task Failure & Rescheduling***

Tasks that fail have their `run_at` rescheduled on an increasing delay **(in seconds)** according to this formula: 
 * 30 + n<sup>4</sup>

Where n = the number of attempts 

Both failing and final_failing will cause the error timestamp and reason to be stored in `:last_fail_at` and `:last_error`.

### Testing With Procrastinator
Procrastinator uses multi-threading and multi-processing internally, which is a nightmare for testing. Fortunately for you, 
Test Mode will disable all of that, and rely on your tests to tell it when to tick. 

Enable Test Mode by setting `Procrastinator.test_mode` to `true` before setting up, or by calling enable_test_mode on 
the procrastination environment. 

```ruby
# all further calls to `Procrastinator.setup` will produce a procrastination environment where Test Mode is enabled
Procrastinator.test_mode = true
 
# or you can also enable it directly in the setup
env = Procrastinator.setup do |env|
   env.enable_test_mode
    
   # other settings...
end
```

In your tests, tell the procrastinator environment to work off one item from its queues: 

```
# works one task on all queues
env.act

# provide queue names to works one task on just those queues
env.act(:cleanup, :email)
```

### Logging
Logging is crucial to knowing what went wrong in an application after the fact, and because Procrastinator runs workers
in separate processes, providing a logger instance isn't really an option. 
 
Instead, provide a directory that your Procrastinator instance should write log entries into:

```ruby
procrastinator = Procrastinator.setup do |env|
   env.log_dir('log/')
end
```
 
Each worker creates its own log named after the queue it is working on (eg. `log/email-queue-worker.log`). The default 
directory is `./log/`, relative to wherever the application is running. Logging will not occur at all if `log_dir` is 
assigned a falsey value. 

The logging level can be set using `log_level` and a value from the Ruby standard library 
[Logger class](https://ruby-doc.org/stdlib-2.2.3/libdoc/logger/rdoc/Logger.html) (eg. `Logger::WARN`, `Logger::DEBUG`, etc.). 

It logs process start at level `INFO`, process termination due to parent disppearance at level `ERROR` and task hooks 
`#success`, `#fail`, and `#final_fail` are at a level `DEBUG`. 

```ruby
procrastinator = Procrastinator.setup do |env|
   env.log_dir('log/')
   env.log_level(Logger::INFO) # setting the default explicity
end
```

## Contributing
Bug reports and pull requests are welcome on GitHub at 
[https://github.com/TenjinInc/procrastinator](https://github.com/TenjinInc/procrastinator).
 
This project is intended to be a friendly space for collaboration, and contributors are expected to adhere to the 
[Contributor Covenant](http://contributor-covenant.org) code of conduct.

### Core Developers
After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can 
also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the 
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, 
push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
