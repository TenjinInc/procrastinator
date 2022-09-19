# Procrastinator

A storage-agnostic job queue gem in plain Ruby.

## Big Picture

Define **Task Handler** classes like this:

```ruby
# Sends a welcome email
class SendWelcomeEmail
   attr_accessor :container, :logger, :scheduler

   def run
      # ... etc
   end
end
```

Then build a task **Scheduler**:

```ruby
scheduler = Procrastinator.setup do |config|
   config.with_store some_email_task_database do
      config.define_queue :welcome, SendWelcomeEmail
      config.define_queue :birthday, SendBirthdayEmail, max_attempts: 3
   end

   config.define_queue :thumbnail, GenerateThumbnail, store: 'imgtasks.csv', timeout: 60
end
```

And **defer** tasks:

```ruby
scheduler.defer(:welcome, data: 'elanor@example.com')

scheduler.defer(:thumbnail, data: {file: 'forcett.png', width: 100, height: 150})

scheduler.defer(:birthday, run_at: Time.now + 3600, data: {user_id: 5})
```

## Contents

* [Installation](#installation)
* [Task Handlers](#task-handlers)
    + [Attribute Accessors](#attribute-accessors)
    + [Errors & Logging](#errors---logging)
* [Configuration](#configuration)
    + [Defining Queues](#defining-queues)
    + [Task Store](#task-store)
        - [Data Fields](#data-fields)
        - [CSV Task Store](#csv-task-store)
        - [Shared Task Stores](#shared-task-stores)
    + [Task Container](#task-container)
* [Deferring Tasks](#deferring-tasks)
    + [Timing](#timing)
    + [Rescheduling Existing Tasks](#rescheduling-existing-tasks)
    + [Retries](#retries)
    + [Cancelling](#cancelling)
* [Running Tasks](#running-tasks)
    + [In Testing](#in-testing)
        - [RSpec Matchers](#rspec-matchers)
    + [In Production](#in-production)
* [Similar Tools](#similar-tools)
    + [Linux etc: Cron and At](#linux-etc--cron-and-at)
    + [Gem: Resque](#gem--resque)
    + [Gem: Rails ActiveJob / DelayedJob](#gem--rails-activejob---delayedjob)
* [Contributing](#contributing)
    + [Developers](#developers)
* [License](#license)

<!-- ToC generated with http://ecotrust-canada.github.io/markdown-toc/ -->

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'procrastinator'
```

And then run in a terminal:

    bundle install

## Task Handlers

Task Handlers are what actually get run on the task queue. They'll look like this:

```ruby
# This is an example task handler
class MyTask
   # These attributes will be assigned by Procrastinator when the task is run.
   # :data is optional
   attr_accessor :container, :logger, :scheduler, :data

   # Performs the core work of the task. 
   def run
      # ... perform your task ...
   end

   # ==================================
   #          OPTIONAL HOOKS
   # ==================================
   #
   # You can always omit any of the methods below. Only #run is mandatory.
   ##

   # Called after the task has completed successfully.
   # 
   # @param run_result [Object] The result of #run.
   def success(run_result)
      # ...
   end

   # Called after #run raises any StandardError (or subclass).
   # 
   # @param error [StandardError] Error raised by #run
   def fail(error)
      # ...
   end

   # Called after a permanent failure, either because: 
   #   1. the current time is after the task's expire_at time.
   #   2. the task has failed and the number of attempts is equal to or greater than the queue's `max_attempts`. 
   #
   # If #final_fail is executed, then #fail will not.
   # 
   # @param error [StandardError] Error raised by #run
   def final_fail(error)
      # ...
   end
end
```

### Attribute Accessors

Task Handlers have attributes that are set after the Handler is created. The attributes are enforced early on to prevent
the tasks from referencing unknown variables at whatever time they are run - if they're missing, you'll get
a `MalformedTaskError`.

| Attribute  | Required | Description | 
|------------|----------|-------------|
|`:container`| Yes   | Container declared in `#setup` from the currently running instance |
|`:logger`   | Yes   | Logger object for the Queue |
|`:scheduler`| Yes   | A scheduler object that you can use to schedule new tasks (eg. with `#defer`)|
|`:data`     | No       | Data provided to `#defer`. Calls to `#defer` will error if they do not provide data when expected and vice-versa. |

### Errors & Logging

Errors that trigger `#fail` or `#final_fail` are saved to the task storage under keywords `last_error` and
`last_fail_at`.

Each queue worker also keeps a logfile log using the Ruby
[Logger class](https://ruby-doc.org/stdlib-2.7.1/libdoc/logger/rdoc/Logger.html). Log files are named after the queue (
eg. `log/welcome-queue-worker.log`).

```ruby
scheduler = Procrastinator.setup do |config|
   # you can set custom log location and level:
   config.log_with(directory: '/var/log/myapp/', level: Logger::DEBUG)

   # you can also set the log rotation age or size (see Logger docs for details)
   config.log_with(shift: 1024, age: 5)

   # use a falsey log level to disable logging entirely:
   config.log_with(level: false)
end
```

The logger can be accessed in your tasks by calling `logger` or `@logger`.

```ruby
# Example handler with logging
class MyTask
   attr_accessor :container, :logger, :scheduler

   def run
      logger.info('This task got run. Hooray!')
   end
end
```

Some events are always logged by default:

|event               |level  |
|--------------------|-------|
|Task completed      | INFO  |
|Task cailure        | ERROR |

## Configuration

`Procrastinator.setup` allows you to define which queues are available and other general settings.

```ruby
require 'procrastinator'

scheduler = Procrastinator.setup do |config|
   # ...
end
```

It then returns a **Task Scheduler** that your code can use to defer tasks.

### Defining Queues

In setup, call `#define_queue` with a symbol name and that queue's Task Handler class:

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
write tasks in your data storage (eg. database, HTTP API, CSV file, microdot, etc).

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
   their final form (eg. `:data` will already be serialized). Each hash must contain the properties listed in
   the [Data Fields](#data-fields) table.

2. `#create(queue:, run_at:, initial_run_at:, expire_at:, data:)`

   Saves a task in your storage. Receives a hash with [Data Fields](#data-fields) keys:
   `:queue`, `:run_at`, `:initial_run_at`, `:expire_at`, and `:data`.

3. `#update(id, new_data)`

   Saves the provided full [Data Fields](#data-fields) hash to your datastore.

4. `#delete(id)`

   Deletes the task with the given identifier from storage

Procrastinator comes with a simple CSV file task store by default, but you are encouraged to build one that suits your
situation.

_Warning_: Task stores shared between queues **must** be thread-safe if using threaded or daemonized work modes.

#### Data Fields

These are the data fields for each individual scheduled task. When using the built-in task store, these are the field
names. If you have a database, use this to inform your table schema.

|  Hash Key         | Type     | Description                                                             |
|-------------------|----------| ------------------------------------------------------------------------|
| `:id`             | integer  | Unique identifier for this exact task                                   |
| `:queue`          | symbol   | Name of the queue the task is inside                                    | 
| `:run_at`         | datetime | Time to attempt running the task next. Updated for retries¹             |
| `:initial_run_at` | datetime | Original `run_at` value. Reset if `#reschedule` is called.              |
| `:expire_at`      | datetime | Time to permanently fail the task because it is too late to be useful   |
| `:attempts`       | integer  | Number of times the task has tried to run                               |
| `:last_fail_at`   | datetime | Time of the most recent failure                                         |
| `:last_error`     | string   | Error message + backtrace of the most recent failure. May be very long. |
| `:data`           | JSON     | Data to be provided to the task handler, serialized² to JSON.            |

¹ `nil` indicates that it is permanently failed and will never run, either due to expiry or too many attempts.

² Serialized using `JSON.dump` and `JSON.parse` with **symbolized keys**. It is strongly recommended to only supply
simple data types (eg. id numbers) to reduce storage space, eliminate redundancy, and reduce the chance of a
serialization error.

Times are all handled as Ruby stdlib Time objects.

#### CSV Task Store

Specifying no storage will cause Procrastinator to save tasks using the very basic built-in CSV storage. It is not
designed for heavy loads, so you should replace it in a production environment.

The default file path is defined in `Procrastinator::Store::SimpleCommaStore::DEFAULT_FILE`.

```ruby
Procrastinator.setup do |config|
   # this will use the default CSV task store. 
   config.define_queue(:reminder, ReminderTask)
end
```

#### Shared Task Stores

When there are tasks that use the same storage, you can wrap them in a `with_store` block.

```ruby
email_task_store = EmailTaskStore.new # eg. some SQL task storage class you wrote

Procrastinator.setup do |config|
   with_store(email_task_store) do
      # queues defined inside this block will use the email task store
      config.define_queue(:welcome, WelcomeTask)
      config.define_queue(:reminder, ReminderTask)
   end

   # and this will not use it
   config.define_queue(:thumbnails, ThumbnailTask)
end
```

### Task Container

Whatever is given to `#provide_container` will be available to Task Handlers via the `:container` attribute and it is
intended for dependency injection.

```ruby
Procrastinator.setup do |config|
   config.provide_container lunch: 'Lasagna'

   # .. other setup stuff ...
end

# ... and in your task ...
class LunchTask
   attr_accessor :container, :logger, :scheduler

   def run
      logger.info("Today's Lunch is: #{ container[:lunch] }")
   end
end
```

## Deferring Tasks

To add tasks to a queue, call `#defer` on the scheduler returned by `Procrastinator.setup`:

```ruby
scheduler = Procrastinator.setup do |config|
   config.define_queue :reminder, EmailEveryone
   config.define_queue :thumbnail, CreateThumbnail
end

# Provide the queue name and any data you want passed in, if needed
scheduler.defer(:reminder)
scheduler.defer(:thumbnail, data: 'forcett.png')
``` 

If there is only one queue, you may omit the queue name:

```ruby
thumbnailer = Procrastinator.setup do |config|
   config.define_queue :thumbnail, CreateThumbnail
end

thumbnailer.defer(data: 'forcett.png')
```

### Timing

You can specify a particular timeframe that a task may be run. The default is to run immediately and never expire.

Be aware that the task is not guaranteed to run at a precise time; the only promise is that the task won't be tried *
before* `run_at` nor *after* `expire_at`.

Tasks attempted after `expire_at` will be final-failed. Setting `expire_at` to `nil`
means it will never expire (but may still fail permanently if, say, `max_attempts` is reached).

```ruby
run_time    = Time.new(2016, 9, 19)
expire_time = Time.new(2016, 9, 20)

# runs on or after 2016 Sept 19, never expires
scheduler.defer(:greeting, run_at: run_time, data: 'elanor@example.com')

# can run immediately but not after 2016 Sept 20
scheduler.defer(:greeting, expire_at: expire_time, data: 'mendoza@example.com')

# can run immediately but not after 2016 Sept 20
scheduler.defer(:greeting, run_at: run_time, expire_at: expire_time, data: 'tahani@example.com')
```

### Rescheduling Existing Tasks

Call `#reschedule` with the queue name and some task-identifying information and then chain `#to` with the new time.

```ruby
run_time    = Time.new(2016, 9, 19)
expire_time = Time.new(2016, 9, 20)

scheduler.defer(:reminder, run_at: Time.at(0), data: 'chidi@example.com')

# we can reschedule the task that matches this data
scheduler.reschedule(:reminder, data: 'chidi@example.com').to(run_at: run_time)

# we can also change the expiry time
scheduler.reschedule(:reminder, data: 'chidi@example.com').to(expire_at: expire_time)

# or both
scheduler.reschedule(:reminder, data: 'chidi@example.com').to(run_at:    run_time,
                                                              expire_at: expire_time)
```

Rescheduling changes the task's...

* `:run_at` and `:initial_run_at` to a new value, if provided
* `:expire_at` to a new value if provided.
* `:attempts` to `0`
* `:last_error` and `:last_error_at` to `nil`.

Rescheduling will not change `:id`, `:queue` or `:data`.

A `RuntimeError` is raised if the new run_at is after expire_at.

### Retries

Failed tasks are automatically retried, with their `run_at` updated on an increasing delay (in seconds) according to
this formula:

> 30 + number_of_attempts<sup>4</sup>

Situations that call `#fail` or `#final_fail` will cause the error timestamp and reason to be stored in `:last_fail_at`
and `:last_error`.

### Cancelling

Call `#cancel` with the queue name and some task-identifying information to narrow the search to a single task.

```ruby
run_time = Time.parse('April 1')
scheduler.defer(:reminder, run_at: run_time, data: 'derek@example.com')

# we can cancel the task made above using whatever we know about it
# An error will be raised if it matches multiple tasks or finds none
scheduler.cancel(:reminder, run_at: run_time, data: 'derek@example.com')

# you could also use the id number directly, if you have it
scheduler.cancel(:reminder, id: 137)
```

## Testing with Procrastinator

Working serially performs tasks from each queue sequentially. There is no multithreading or daemonizing.

Call `work` on the Scheduler with an optional list of queues to filter by.

```ruby
# work just one task
scheduler.work.serially

# work the first five tasks
scheduler.work.serially(steps: 5)

# only work tasks on greeting and reminder queues
scheduler.work(:greeting, :reminders).serially(steps: 2)
```

### RSpec Matchers

A `have_task` RSpec matcher is defined to make testing task scheduling a little easier.

```ruby
# Note: you must require the matcher file separately
require 'procrastinator'
require 'procrastinator/rspec/matchers'

task_storage = TaskStore.new

scheduler = Procrastinator.setup do |config|
   config.define_queue :welcome, SendWelcome, store: task_storage
end

scheduler.defer(data: 'tahani@example.com')

expect(task_storage).to have_task(data: 'tahani@example.com')
```

## Running Tasks

When you are ready to run a Procrastinator daemon in production, you may use some provided Rake tasks.

In your Rake file call `DaemonTasks.define` with a block that constructs a scheduler instance.

```ruby
# Rakefile
require 'rake'
require 'procrastinator/rake/daemon_tasks'

# Defines a set of tasks that will control a Procrastinator daemon
# Default pid_path is /tmp/procrastinator.pid
Procrastinator::Rake::DaemonTasks.define do
   Procrastinator.setup do
      # ... etc ...
   end
end
```

You can name the daemon process by specifying the pid_path with a specific .pid file. If does not end with '.pid' it is
assumed to be a directory name, and `procrastinator.pid` is appended.

```ruby
# Rakefile

# This would define a process titled my-app
Procrastinator::Rake::DaemonTasks.define(pid_path: 'my-app.pid') do
   # ... build a Procrastinator instance here ...
end

# equivalent to ./pids/procrastinator.pid
Procrastinator::Rake::DaemonTasks.define(pid_path: 'pids') do
   # ... build a Procrastinator instance here ...
end
```

Either run the generated Rake tasks in a terminal or with your daemon monitoring tool of choice (eg. Monit, systemd)

```bash
# In terminal
bundle exec rake procrastinator:start
bundle exec rake procrastinator:status
bundle exec rake procrastinator:restart
bundle exec rake procrastinator:stop
```

There are instructions for using Procrastinator with Monit in
the [github wiki](https://github.com/TenjinInc/procrastinator/wiki/Monit-Configuration).

## Similar Tools

Procrastinator is a library that exists to enable job queues with flexibility in storage mechanism and minimal
dependencies. It's neat but it is specifically intended for smaller datasets. Some other approaches include:

### Linux etc: Cron and At

Consider [Cron](https://en.wikipedia.org/wiki/Cron) for tasks that run on a regular schedule.

Consider [At](https://en.wikipedia.org/wiki/At_(command)) for tasks that run once at a particular time.

While neither tool natively supports retry, they can be great solutions for simple situations.

### Gem: Resque

Consider [Resque](https://rubygems.org/gems/resque) for larger datasets (eg. 10,000+ jobs) where performance
optimization becomes relevant.

### Gem: Rails ActiveJob / DelayedJob

Consider [DelayedJob](https://rubygems.org/gems/delayed_job) for projects that are tightly integrated with Rails and
fully commit to live in that ecosystem.

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

Docs are generated using YARD. Run `rake yard` to generate a local copy.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
