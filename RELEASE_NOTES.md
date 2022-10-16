# Release Notes

## 1.1.0 (       )

### Major Changes

* none

### Minor Changes

* Removed process name limit.

### Bugfixes

* have_task matcher:
    * Fixed have_task handling of nested matchers like be_within
    * Improved have_task handling of string queue names vs symbols

## 1.0.1 (2022-09-20)

### Major Changes

* none

### Minor Changes

* none

### Bugfixes

* Fixed integration error in rescheduling tasks

## 1.0.0 (2022-09-18)

### Major Changes

* Minimum supported Ruby is now 2.4
* Added generic `Procrastinator::Config#log_with`
    * Removed `Procrastinator::Config#log_inside`
    * Removed `Procrastinator::Config#log_at_level`
    * falsey log level is now the control for whether logging occurs, instead of falsey log directory
* Queues are managed as threads rather than sub processes
    * These unnecessary methods no longer exist:
        * `Procrastinator.test_mode`
        * `Procrastinator::Config#enable_test_mode`
        * `Procrastinator::Config#test_mode?`
        * `Procrastinator::Config#test_mode`
        * `Procrastinator::Config#prefix`
        * `Procrastinator::Config#pid_dir`
        * `Procrastinator::Config#each_process`
        * `Procrastinator::Config#run_process_block`
    * Removed use of envvar `PROCRASTINATOR_STOP`
    * `Procrastinator::QueueManager` is merged into `Procrastinator::Scheduler`
    * Removed rake task to halt individual queue processes
    * Renamed `Procrastinator::Config#provide_context` to `provide_container`
    * You must now call `Scheduler#work` on the result of `Procrastinator.config`
    * Use a dedicated process monitor (like `monit`) instead in production environments to maintain uptime
* `max_tasks` is removed as it only added concurrency complexity. Each queue worker only selects one task from only its
  queue.
* Data is now stored as JSON instead of YAML
* Added with_store that applies its settings to its block
    * `load_with` has been removed
* Removed `task_attr` and `Procrastinator::Task` module. Tasks is now duck-type checked for accessors instead.
* Added Rake tasks to manage process daemon
* Times are passed to Task Store as a Ruby Time object instead of an epoch time integer
* `#delay` is now `#defer`

### Minor Changes

* Started release notes file
* Updated development gems
* Logs now include the queue name in log lines
* Logs can now set the shift size or age (like Ruby's Logger)
* Log format is now tab-separated to align better and work with POSIX cut
* General renaming of terms

### Bugfixes

* none 
