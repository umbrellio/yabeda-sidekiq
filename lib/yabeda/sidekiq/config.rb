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

      attr_config gather_generic_sidekiq_metrics: false

      # Adds a +state+ label (+paused+ or +unpaused+) to the per-queue cluster metrics:
      # +sidekiq_jobs_waiting_count+ and +sidekiq_queue_latency+.
      #
      # Disabled by default for two reasons:
      #  - it costs one extra Redis call per queue on every collection cycle
      #  - it adds a label to metrics that already exist, which changes their time series and
      #    silently breaks recorded rules, alerts and dashboards built on the unlabelled ones
      #
      # Pausing queues is a Sidekiq Pro feature: on OSS Sidekiq every queue is always reported
      # as +unpaused+.
      attr_config show_queue_state: false
    end
  end
end
