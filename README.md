# Procrastinator

Procrastinator is a framework-independent job scheduling gem. It creates a subprocess for each queue that performs 
tasks at the appropriate times. 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'procrastinator'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install procrastinator

## Usage
Setup a procrastination environment:

```ruby
procrastinator = Procrastinator.setup(TaskPersister.new) do |env|   # MyTaskPersister is a class defined by you 
  env.define_queue(:email)
  env.define_queue(:cleanup, max_attempts: 3)
end
```

And then delay some tasks:

```ruby
procrastinator.delay(queue: :email, task: EmailGreeting.new('bob@example.com'))
procrastinator.delay(queue: :cleanup, run_at: Time.now + 3600, task: ClearTempData.new)
```

Read on for more details on each step. 

###`Procrastinator.setup`
The setup phase first defines which queues are available and the persistence strategy to use for reading 
and writing tasks. It then starts up a sub process for working on each queue within that environment.


#### Persister Strategy
The persister instance is the last step between Procrastinator and your data storage (eg. database). As core Procrastinator is framework-agnostic, it needs you to provide an object that knows how to read and write task data. 

Your [strategy](https://en.wikipedia.org/wiki/Strategy_pattern) class is required to provide the following methods: 

* `#read_tasks(queue_name)` - Returns a list of hashes from your data storage. Each hash must contains the properites of one task, as seen in the *Attributes Hash* 
* `#create_task(data)` - Creates a task in your datastore. Receives a hash with keys `:queue`, `:run_at`, `:initial_run_at`, `:expire_at`, and `:task` as described in *Attributes Hash* 
* `#update_task(attributes)` - Receives the Attributes Hash as the data to be saved
* `#delete_task(id)` - Deletes the task with the given id. 

If the strategy does not have all of these methods, Procrastinator will explode with a `MalformedPersisterError`  and you will be sad. 

***Attributes Hash***

|  Hash Key         | Type   | Description                                                                           |
|-------------------|--------| --------------------------------------------------------------------------------------|
| `:id`             | int    | Unique identifier for this exact task                                                 |
| `:queue`          | symbol | Name of the queue the task is inside                                                      | 
| `:run_at`         | int    | Unix timestamp of when to next attempt running the task                               |
| `:initial_run_at` | int    | Unix timestamp of the original run_at; before the first attempt, this is equal to run_at |
| `:expire_at`      | int    | Unix timestamp of when to permanently fail the task because it is too late to be useful |
| `:attempts`       | int    | Number of times the task has tried to run; this should only be > 0 if the task fails  |
| `:last_fail_at`   | int    | Unix timestamp of when the most recent failure happened                               |
| `:last_error`     | string | Error message + bracktrace of the most recent failure. May be very long.              |
| `:task`           | string | YAML-dumped ruby object definition of the task.                                       |

Notice that the times are all given as unix epoch timestamps. This is to avoid any confusion with timezones, and it is recommended that you store times in this manner for the same reason. 

####Defining Queues
`Procrastinator.setup` requires a block be provided, and that in the block call `#define_queue` be called on the provided environment. Define queue takes a queue name symbol and these properies as a hash

 * :timeout - Time, in seconds, after which it should fail tasks in this queue for taking too long to execute.
 * :max_attempts - Maximum number of attempts for tasks in this queue. If attempts is >= max_attempts, the task will be final_failed and marked to never run again
 * :update_period - Delay, in seconds, between refreshing the task list from the persister
 * :max_tasks - The maximum number of tasks to run concurrently with multi-threading. 

**Examples**
```ruby 
Procrastinator.setup(some_persister) do |env|
   env.define_queue(:email)
   
   # with all defaults set explicitly
   env.define_queue(:email, timeout: 3600, max_attempts: 20, update_period: 10, max_tasks: 10)
end
```
  
#### Queue Sub-Processes
Each queue is worked in a separate process, and each process is multi-threaded to handle more than one task at a time. This should help prevent a single task from clogging up the whole queue, or a single queue clogging up the entire system. Tasks are chosen by their `:run_at` property. 

The sub-processes check ervey 5 seconds that the parent process is still alive. If there is no process with the parent's process ID, the sub-process will self-exit. 

###`Environment#delay`
When there are multiple queues defined, you are required to provide a queue name:

```ruby
procrastinator = Procrastinator.setup(task_persister) do |env|
   env.define_queue(:email)
   env.|env|define_queue(:cleanup)
end

procrastinator.delay(:email, task: EmailReminder.new('bob@example.com'))
```

Otherwise, Procrastinator will let you be lazy: 

```ruby
procrastinator = Procrastinator.setup(task_persister) do |env|
   env.define_queue(:email)
end

procrastinator.delay(task: EmailReminder.new('bob@example.com'))
```

You can set when the particular task is to be run and/or when it should expire. Be aware that neither is guaranteed to be real-time; a task will run as soon as it possible after `run_at` is passed, and will expire once it attempts to run after `expire_at` has passed. 

```ruby
procrastinator = Procrastinator.setup(task_persister) do |env|
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
   env.define_queue(:email)
end

procrastinator.delay(expire_at: , task: EmailGreeting.new('bob@example.com'))

# explicitly setting default
procrastinator.delay(expire_at: nil, task: EmailGreeting.new('bob@example.com'))
```

#### Task
Like the persister provided to `.setup`, your task is a strategy object that fills in the details of what to do. For this, 
your task **must provide** a `#run` method:

 * `#run` - Performs the core work of the task.

You may also optionally provide these hook methods, which are run during different points in the process:

 * `#success` - run after the task has completed successfully 
 * `#fail` - run after the task has failed due to `#run` producing a `StandardError` or subclass.
 * `#final_fail` - run after the task has failed for the last time because either:
    1. the number of attempts is >= the `max_attempts` defined for the queue; or
    2. the time reported by `Time.now` is past the task's `expire_at` time.

If a task reaches `#final_fail` it will be marked to never be run again.

***Task Failure & Rescheduling***

Tasks that fail have their `run_at` rescheduled on an increasing delay according to this formula: 
 * 30 + attempts<sup>4</sup> **(in seconds)**

Both failing and final_failing will cause the error timestamp and reason to be stored in `:last_fail_at` and `:last_error`.

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