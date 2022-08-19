# Release Notes

## 1.0.0 (       )

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
    * Removed rake task to halt queue processes
    * Renamed `Procrastinator::Config#provide_context` to `provide_container`
    * You must now call `Scheduler#work` on the result of `Procrastinator.config`
    * Use a dedicated process monitor (like `monit`) instead in production environments
    * Suuply a block to `daemonized!` to run code in the spawned process.
* `max_tasks` is removed as it only added concurrency complexity
* Data is now stored as JSON instead of YAML
* Added store_with that applies its settings to its block
   * `load_with` has been removed

### Minor Changes

* Started release notes file
* Updated development gems
* Logs now include the queue name in log lines
* Logs can now set the shift size or age (like Ruby's Logger)

### Bugfixes

* none 
