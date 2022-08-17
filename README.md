# Procrastinator

Procrastinator is a pure Ruby job scheduling gem. Put off tasks until later (or at least let another process handle it).

If the task fails to complete or takes too long, it delays it and tries again later.

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
   env.define_queue :greeting, SendWelcomeEmail, store: 'tasks.csv'
   env.define_queue :thumbnail, GenerateThumbnail, store: 'tasks.csv', timeout: 60
   env.define_queue :birthday, SendBirthdayEmail, store: 'tasks.csv', max_attempts: 3
end
```

And then - eventually - do some work:

```ruby
# starts a thread for each queue. Other options: Single-process or daemonized
scheduler.work.threaded

scheduler.delay(:greeting, data: 'bob@example.com')

scheduler.delay(:thumbnail, data: {file: 'full_image.png', width: 100, height: 100})

scheduler.delay(:send_birthday_email, run_at: Time.now + 3600, data: {user_id: 5})
```

## Contents

- [Installation](#installation)
- [Setup](#setup)
    * [Defining Queues](#defining-queues)
    * [Task Store](#task-store)
        + [Data Fields](#data-fields)
    * [Task Container](#task-container)
- [Tasks](#tasks)
    * [Accessing Task Attributes](#accessing-task-attributes)
    * [Errors & Logging](#errors-logging)
- [Scheduling Tasks](#scheduling-tasks)
    * [Providing Data](#providing-data)
    * [Scheduling](#scheduling)
    * [Rescheduling](#rescheduling)
    * [Retries](#retries)
    * [Cancelling](#cancelling)
- [Working on Tasks](#working-on-tasks)
    * [Stepwise Working](#stepwise-working)
    * [Threaded Working](#threaded-working)
    * [Daemonized Working](#daemonized-working)
        + [PID Files](#pid-files)
- [Contributing](#contributing)
    * [Developers](#developers)
- [License](#license)

<!-- ToC generated with http://ecotrust-canada.github.io/markdown-toc/ -->

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'procrastinator'
```

And then run:

    bundle install

## Setup

`Procrastinator.setup` allows you to define which queues are available and other settings.

```ruby
require 'procrastinator'

scheduler = Procrastinator.setup do |config|
   # ...
end
```

It then returns a `Scheduler` that your code can use to schedule tasks or tell to start working.

* See [Scheduling Tasks](#scheduling-tasks)
* See [Start Working](#start-working)

### Defining Queues

In setup, call `#define_queue` with a symbol name and the class that performs those jobs:

```ruby
   # You must provide a queue name and the class that handles those jobs
config.define_queue :greeting, SendWelcomeEmail

# but queues have some optional settings, too
config.define_queue :greeting, SendWelcomeEmail, store: 'tasks.csv', timeout: 60, max_attempts: 2, update_period: 1

# all defaults set explicitly
config.define_queue :greeting, SendWelcomeEmail, store: 'procrastinator.csv', timeout: 3600, max_attempts: 20, update_period: 10
```

Description of keyword options:

| Option           | Description   |
|------------------| ------------- |
| `:store`         | Storage IO object for tasks. See [Task Store](#task-store)     |
| `:timeout`       | Max duration (seconds) before tasks are failed for taking too long  |
| `:max_attempts`  | Once a task has been attempted `max_attempts` times, it will be permanently failed. |
| `:update_period` | Delay (seconds) between reloads of all tasks from the task store  |

### Task Store

A task store is a [strategy](https://en.wikipedia.org/wiki/Strategy_pattern) pattern object that knows how to read and
write tasks in your data storage (eg. database, CSV file, etc).

```ruby
task_store = ReminderStore.new # eg. some SQL task storage class you wrote

Procrastinator.setup do |config|
   config.define_queue(:reminder, ReminderTask, store: task_store)

   # to use the default CSV storage, provide :store with a string or Pathname
   config.define_queue(:reminder, ReminderTask, store: '/var/myapp/tasks.csv')
end
```

A task store is required to implement *all* of the following methods or else it will raise a
`MalformedPersisterError`:

1. `#read(attributes)`

   Returns a list of hashes from your datastore that match the given attributes hash. The search attributes will be in
   their final form (eg. `:data` will already be serialized). Each hash must contain the properties listed
   in [Task Data](#task-data) below.

2. `#create(queue:, run_at:, initial_run_at:, expire_at:, data:)`

   Saves a task in your storage. Receives a hash with [Task Data](#task-data) keys:
   `:queue`, `:run_at`, `:initial_run_at`, `:expire_at`, and `:data`.

3. `#update(id, new_data)`

   Saves the provided full [Task Data](#task-data) hash to your datastore.

4. `#delete(id)`

   Deletes the task with the given identifier from storage

Procrastinator comes with a simple CSV file task store by default, but you are encouraged to build one that suits your
situation.

#### Data Fields

These are the data fields for each individual scheduled task. When using the built-in task store, these are the field
names. If you have a database, use this to inform your table schema.

|  Hash Key         | Type   | Description                                                                             |
|-------------------|--------| ----------------------------------------------------------------------------------------|
| `:id`             | int    | Unique identifier for this exact task                                                   |
| `:queue`          | symbol | Name of the queue the task is inside                                                    | 
| `:run_at`         | int    | Unix timestamp of when to next attempt running the task. ¹                              |
| `:initial_run_at` | int    | Unix timestamp of the originally requested run                                          |
| `:expire_at`      | int    | Unix timestamp of when to permanently fail the task because it is too late to be useful |
| `:attempts`       | int    | Number of times the task has tried to run; this should only be > 0 if the task fails    |
| `:last_fail_at`   | int    | Unix timestamp of when the most recent failure happened                                 |
| `:last_error`     | string | Error message + bracktrace of the most recent failure. May be very long.                |
| `:data`           | string | Serialized data accessible in the task instance.²                                       |

> ¹ If `nil`, that indicates that it is permanently failed and will never run, either due to expiry or too many attempts.

> ² Serialized using JSON.dump and JSON.parse with symbolized keys

Strongly recommended to keep to simple data types (eg. id numbers) to reduce storage space, eliminate redundancy, and
reduce the chance of a serialization error.

Times are all stored as unix epoch integer timestamps. This is to avoid confusion or conversion errors with timezones or
daylight savings.

### Task Container

Whatever is given to `#provide_container` will available to Tasks through the task attribute `:container`.

This can be useful for things like app containers, but you can use it for whatever you like.

```ruby
Procrastinator.setup do |env|
   env.provide_container lunch: 'Lasagna'

   # .. other setup stuff ...
end

# ... and in your task ...
class LunchTask
   include Procrastinator::Task

   task_attr :container

   def run
      logger.info("Today's Lunch is: #{ container[:lunch] }")
   end
end
```

## Tasks

Your task class is what actually gets run on the task queue. They'll look like:

```ruby

class MyTask
   include Procrastinator::Task

   # Give any of these symbols to task_attr and they will become available as methods
   # task_attr :data, :logger, :container, :scheduler

   # Performs the core work of the task. 
   def run
      # ... perform your task ...
   end

   # ========================================
   #             OPTIONAL HOOKS
   #
   # You can always omit any of the methods
   # below. Only #run is mandatory.
   #
   # ========================================

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

### Accessing Task Attributes

Include `Procrastinator::Task` in your task class and then use `task_attr` to register which task attributes your task
needs.

```ruby

class MyTask
   include Procrastinator::Task

   # declare the task attributes you care about by calling task_attr. 
   # You can use any of these symbols: 
   #             :data, :logger, :container, :scheduler
   task_attr :data, :logger

   def run
      # the attributes listed in task_attr become methods like attr_accessor
      logger.info("The data for this task is #{ data }")
   end
end
```

* `:data`
  This is the data that you provided in the call to `#delay`. Any task that registers `:data` as a task attribute will
  require data be passed to `#delay`. See [Task Data](#task-data) for more.

* `:container`

  The container you've provided in your setup. See [Task Container](#task-container) for more.

* `:logger`

  The queue's Logger object. See [Logging](#logging) for more.

* `:scheduler`

  A scheduler object that you can use to schedule new tasks (eg. with `#delay`).

### Errors & Logging

Errors that trigger `#fail` or `#final_fail` are saved to the task storage under columns `last_error` and
`last_error_at`.

Each queue worker also keeps a logfile log using the Ruby
[Logger class](https://ruby-doc.org/stdlib-2.7.1/libdoc/logger/rdoc/Logger.html). Log files are named after the queue (
eg. `log/welcome-queue-worker.log`).

```ruby
scheduler = Procrastinator.setup do |env|
   # you can set custom log location and level:
   env.log_with(directory: '/var/log/myapp/', level: Logger::DEBUG)

   # you can also set the log rotation age or size (see Logger docs for details)
   env.log_with(shift: 1024, age: 5)

   # use a falsey log level to disable logging entirely:
   env.log_with(level: false)
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

Some events are already logged for you:

|event               |level  |
|--------------------|-------|
|process started     | INFO  |
|#success called     | DEBUG |
|#fail called        | DEBUG |
|#final_fail called  | DEBUG |

## Scheduling Tasks

To schedule tasks, just call `#delay` on the environment returned from `Procrastinator.setup`:

```ruby
scheduler = Procrastinator.setup do |env|
   env.define_queue :reminder, EmailReminder
   env.define_queue :thumbnail, CreateThumbnail
end

# Provide the queue name and any data you want passed in
scheduler.delay(:reminder, data: 'bob@example.com')
``` 

If there is only one queue, you may omit the queue name:

```ruby
scheduler = Procrastinator.setup do |env|
   env.define_queue :reminder, EmailReminder
end

scheduler.delay(data: 'bob@example.com')
```

### Providing Data

Most tasks need some additional information to complete their work, like id numbers,

The `:data` parameter is serialized to string as YAML, so it's better to keep it as simple as possible. For example, if
you have a database instead of passing in a complex Ruby object, pass in just the primary key and reload it in the
task's `#run`. This will require less space in your database and avoids obsolete or duplicated information.

### Scheduling

You can set when the particular task is to be run and/or when it should expire. Be aware that the task is not guaranteed
to run at a precise time; the only promise is that the task will be attempted *after* `run_at` and before `expire_at`.

```ruby
# runs on or after 1 January 3000
scheduler.delay(:greeting, run_at: Time.new(3000, 1, 1), data: 'philip_j_fry@example.com')

# run_at defaults to right now:
scheduler.delay(:thumbnail, run_at: Time.now, data: 'shut_up_and_take_my_money.gif')
```

You can also set an `expire_at` deadline. If the task has not been run before `expire_at` is passed, then it will be
final-failed the next time it would be attempted. Setting `expire_at` to `nil` means it will never expire (but may still
fail permanently if, say, `max_attempts` is reached).

```ruby
# will not run at or after 
scheduler.delay(:happy_birthday, expire_at: Time.new(2018, 03, 17, 12, 00, '-06:00'), data: 'contact@tenjin.ca')

# expire_at defaults to nil:
scheduler.delay(:greeting, expire_at: nil, data: 'bob@example.com')
```

### Rescheduling

Call `#reschedule` with the queue name and some identifying information, and then calling #to on that to provide the new
time.

```ruby
scheduler = Procrastinator.setup do |env|
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

Rescheduling sets the task's:

* `:run_at` and `:initial_run_at` to a new value, if provided
* `:expire_at` to a new value if provided.
* `:attempts` to `0`
* `:last_error` and `:last_error_at` to `nil`.

Rescheduling will not change `:id`, `:queue` or `:data`. A `RuntimeError` is raised if the runtime is after the expiry.

### Retries

Failed tasks have their `run_at` rescheduled on an increasing delay (in seconds) according to this formula:

> 30 + (number_of_attempts)<sup>4</sup>

Situations that call `#fail` or `#final_fail` will cause the error timestamp and reason to be stored in `:last_fail_at`
and `:last_error`.

### Cancelling

Call `#cancel` with the queue name and some identifying information to narrow the search to a single task.

```ruby
scheduler = Procrastinator.setup do |env|
   env.define_queue :reminder, EmailReminder
end

scheduler.delay(:reminder, run_at: Time.parse('June 1'), data: 'bob@example.com')

# we can cancel the task made above using whatever we know about it, like the saved :data
scheduler.reschedule(:reminder, data: 'bob@example.com')

# or multiple attributes
scheduler.reschedule(:reminder, run_at: Time.parse('June 1'), data: 'bob@example.com')

# you could also use the id number directly, if you have it
scheduler.reschedule(:reminder, id: 137)
```

## Working on Tasks

Use the scheduler object returned by setup to `#work` queues **serially**, **threaded**, or **daemonized**.

### Serial Working

Working serially performs a task from each queue directly. There is no multithreading or daemonizing.

Work serially for TDD tests or other situations you need close direct control.

```ruby
# work just one task, no threading
scheduler.work.serially

# work the first five tasks
scheduler.work.serially(steps: 5)

# only work tasks on greeting and reminder queues
scheduler.work(:greeting, :reminders).serially(steps: 2)
```

### Threaded Working

Threaded working will spawn a worker thread per queue.

Use threaded working for task queues that should only run while the main application is running. This includes the usual
caveats around multithreading, so proceed with caution.

```ruby
# work tasks until the application exits
scheduler.work.threaded

# work tasks for 5 seconds
scheduler.work.threaded(timeout: 5)

# only work tasks on greeting and reminder queues
scheduler.work(:greeting, :reminders).threaded
```

### Daemonized Working

Daemonized working **consumes the current process** and then proceeds with threaded working in the new daemon.

Use daemonized working for production environments, especially in conjunction with daemon monitors
like [Monit](https://mmonit.com/monit/). Provide a block to daemonized! to get

```ruby
# work tasks forever as a headless daemon process.
scheduler.work.daemonized!

# you can specify the new process name and the directory to save the procrastinator.pid file 
scheduler.work.daemonized!(name: 'myapp-queue', pid_path: '/var/run')

# ... or set the pid file name precisely by giving a .pid path
scheduler.work.daemonized!(pid_path: '/var/run/myapp.pid')

# only work tasks in the 'greeting' and 'reminder' queues
scheduler.work(:greeting, :reminders).daemonized!

# supply a block to run code after the daemon subprocess has forked off
scheduler.work.daemonized! do
   # this gets run after the daemon is spawned
   task_store.reconnect_mysql
end
```

Procrastinator endeavours to be thread-safe and support concurrency, but this flexibility allows for many possible
combinations.

Expected use is a single process with one thread per queue. More complex use is possible but Procrastinator can't
guarantee concurrency in your Task Store.

#### PID Files

Process ID files are a single-line file that saves the daemon's process ID number. It's saved to the directory given
by `:pid_dir`. The default location is `pids/` relative to the file that called `#daemonized!`.

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
