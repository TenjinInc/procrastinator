# Procrastinator

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/procrastinator`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

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
# you must provide queue definitions and a persistence strategy
procrastinator = Procrastinator.setup(email: cleanup: )
```

And then delay a task:

```ruby
# you must provide a queue name if there is more than one queue
procrastinator.delay()
```

Read on for more details on each step. 

###`Procrastinator.setup`

* requires a hash of queue definitions.
* requires a persister strategy
* creates a subprocess for each queue. That process will work off tasks from the queue. 
* returns an Procrastinator::Environment that you may use to delay tasks.

<!--TODO: details about subprocess handling. Should be killed on exit, etc  -->
<!--TODO: details on working off the queue.  -->

<!--TODO: describe timeout  -->
<!--TODO: describe update_period  -->
<!--TODO: describe max_attempts  --> 
<!--TODO: describe max_tasks  -->
 
 <!--TODO: explain that neither persister nor queue hash may be nil, and queue hash must have contents  -->
  
   <!--TODO: explain that if the main process is killed, each queue subprocess will notice within 5 seconds and terminate itself.   --> 




#### Persister Strategy
The strategy <!--TODOlink to strategy pattern--> is expected to provide the following methods: 

* `#read_tasks` <params and return details>
* `#create_task` <params and return details>
* `#delete_task` <params and return details>
* `#update_task` <params and return details>

If your strategy does not provide all of these methods, Procrastinator will explode with a `MalformedPersisterError` 
and you will be sad. 

###`Environment#delay`

* you must provide a queue name if there is more than one queue definition, otherwise an `AmbiguousTaskError` will be raised. 
* describe what run_at, expire_at, task do 

* When providing a date, it is recommended to store an integer (eg. DateTime#to_i), as that will not have any timezone problems. Procrastinator works with ints internally anyway,.  

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
    
<!--TODO: describe how rescheudling works: the algo, rebinding run_at vs initial_run_at  -->
<!--TODO: describe last_error, last_fail_at  --> 

   
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

