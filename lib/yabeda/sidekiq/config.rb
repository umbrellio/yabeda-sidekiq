# frozen_string_literal: true

require "anyway"

module Yabeda
  module Sidekiq
    class Config < ::Anyway::Config
      config_name :yabeda_sidekiq

      # By default all sidekiq worker processes (servers) collects global metrics about whole Sidekiq installation.
      # Client processes (everything else that is not Sidekiq worker) by default doesn't.
      # With this config you can override this behavior:
      #  - force disable if you don't want multiple Sidekiq workers to report the same numbers (that causes excess load to both Redis and monitoring)
      #  - force enable if you want non-Sidekiq process to collect them (like dedicated metric exporter process)
      attr_config collect_cluster_metrics: ::Sidekiq.server?

      # Declare metrics that are only tracked inside worker process even outside them
      attr_config declare_process_metrics: ::Sidekiq.server?

      # Retries are tracked by default as a single metric. If you want to track them separately for each queue, set this to +true+
      # Disabled by default because it is quite slow if the retry set is large
      attr_config retries_segmented_by_queue: false

      # If set to true, an `:error` label will be added with name of the error class to all failed jobs
      attr_config label_for_error_class_on_sidekiq_jobs_failed: false

      # Collects +sidekiq_queue_paused+: 1 when the queue is paused, 0 when it is not.
      #
      # Disabled by default because it costs one extra Redis call per queue on every collection
      # cycle. Enabling it adds a metric and changes no existing one, so it is safe to turn on
      # without touching recorded rules, alerts or dashboards.
      #
      # Pausing queues is a Sidekiq Pro feature: on OSS Sidekiq every queue is always reported
      # as not paused.
      attr_config show_queue_state: false
    end
  end
end
