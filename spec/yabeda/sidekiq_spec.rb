# frozen_string_literal: true

RSpec.describe Yabeda::Sidekiq do
  it "has a version number" do
    expect(Yabeda::Sidekiq::VERSION).not_to be_nil
  end

  it "configures middlewares" do
    config = Sidekiq.respond_to?(:default_configuration) ? Sidekiq.default_configuration : Sidekiq
    expect(config.client_middleware).to include(have_attributes(klass: Yabeda::Sidekiq::ClientMiddleware))
  end

  describe "plain Sidekiq jobs" do
    it "counts enqueues" do
      expect do
        SamplePlainJob.perform_async
        SamplePlainJob.perform_async
        FailingPlainJob.perform_async
      end.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
          { queue: "default", worker: "SamplePlainJob" } => 2,
          { queue: "default", worker: "FailingPlainJob" } => 1,
        )
    end

    context "when label_for_error_class_on_sidekiq_jobs_failed is set to true" do
      around do |example|
        old_value = described_class.config.label_for_error_class_on_sidekiq_jobs_failed
        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = true

        example.run

        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = old_value
      end

      it "counts failed total and executed total with correct labels", sidekiq: :inline do
        expect do
          SamplePlainJob.perform_async
          SamplePlainJob.perform_async
          begin
            FailingPlainJob.perform_async
          rescue StandardError
            nil
          end
        end.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
            { queue: "default", worker: "FailingPlainJob", error: "FailingPlainJob::SpecialError" } => 1,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
              { queue: "default", worker: "SamplePlainJob" } => 2,
              { queue: "default", worker: "FailingPlainJob" } => 1,
            )
      end

      it "does not add jobs_failed_total error label to labels used for jobs_executed_total", sidekiq: :inline do
        expect do
          SamplePlainJob.perform_async
          SamplePlainJob.perform_async
          begin
            FailingPlainJob.perform_async
          rescue StandardError
            nil
          end
        end.not_to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
            { queue: "default", worker: "FailingPlainJob", error: "FailingPlainJob::SpecialError" } => 1,
          )
      end
    end

    describe "re-routing jobs by middleware" do
      around do |example|
        add_reroute_jobs_middleware
        example.run
        remove_reroute_jobs_middleware
      end

      it "counts enqueues" do
        expect do
          SamplePlainJob.perform_async
          SamplePlainJob.perform_async
          FailingPlainJob.perform_async
        end.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
            { queue: "rerouted_queue", worker: "SamplePlainJob" } => 2,
            { queue: "rerouted_queue", worker: "FailingPlainJob" } => 1,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_rerouted_total).with(
              { from_queue: "default", to_queue: "rerouted_queue", worker: "SamplePlainJob" } => 2,
              { from_queue: "default", to_queue: "rerouted_queue", worker: "FailingPlainJob" } => 1,
            )
      end
    end

    it "measures runtime", sidekiq: :inline do
      expect do
        SamplePlainJob.perform_async
        SamplePlainJob.perform_async
        begin
          FailingPlainJob.perform_async
        rescue StandardError
          nil
        end
      end.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
          { queue: "default", worker: "SamplePlainJob" } => 2,
          { queue: "default", worker: "FailingPlainJob" } => 1,
        ).and \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_success_total).with(
            { queue: "default", worker: "SamplePlainJob" } => 2,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
              { queue: "default", worker: "FailingPlainJob" } => 1,
            ).and \
              measure_yabeda_histogram(Yabeda.sidekiq.job_runtime).with(
                { queue: "default", worker: "SamplePlainJob" } => kind_of(Numeric),
                { queue: "default", worker: "FailingPlainJob" } => kind_of(Numeric),
              )
    end
  end

  describe "ActiveJob jobs" do
    it "counts enqueues" do
      expect { SampleActiveJob.perform_later }.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
          { queue: "default", worker: "SampleActiveJob" } => 1,
        )
    end

    describe "re-routing jobs by middleware" do
      around do |example|
        add_reroute_jobs_middleware
        example.run
        remove_reroute_jobs_middleware
      end

      it "counts enqueues" do
        expect { SampleActiveJob.perform_later }.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
            { queue: "rerouted_queue", worker: "SampleActiveJob" } => 1,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_rerouted_total).with(
              { from_queue: "default", to_queue: "rerouted_queue", worker: "SampleActiveJob" } => 1,
            )
      end
    end

    context "when label_for_error_class_on_sidekiq_jobs_failed is set to true" do
      around do |example|
        old_value = described_class.config.label_for_error_class_on_sidekiq_jobs_failed
        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = true

        example.run

        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = old_value
      end

      it "counts enqueues and uses the default label for the error class", sidekiq: :inline do
        expect do
          SampleActiveJob.perform_later
          SampleActiveJob.perform_later
          begin
            FailingActiveJob.perform_later
          rescue StandardError
            nil
          end
        end.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
            { queue: "default", worker: "FailingActiveJob", error: "FailingActiveJob::SpecialError" } => 1,
          )
      end
    end

    it "measures runtime", sidekiq: :inline do
      expect do
        SampleActiveJob.perform_later
        SampleActiveJob.perform_later
        begin
          FailingActiveJob.perform_later
        rescue StandardError
          nil
        end
      end.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
          { queue: "default", worker: "SampleActiveJob" } => 2,
          { queue: "default", worker: "FailingActiveJob" } => 1,
        ).and \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_success_total).with(
            { queue: "default", worker: "SampleActiveJob" } => 2,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
              { queue: "default", worker: "FailingActiveJob" } => 1,
            ).and \
              measure_yabeda_histogram(Yabeda.sidekiq.job_runtime).with(
                { queue: "default", worker: "SampleActiveJob" } => kind_of(Numeric),
                { queue: "default", worker: "FailingActiveJob" } => kind_of(Numeric),
              )
    end
  end

  describe "#yabeda_tags worker method" do
    it "uses custom labels for both sidekiq and application metrics", sidekiq: :inline do
      expect { SampleComplexJob.perform_async }.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
          { queue: "default", worker: "SampleComplexJob", implicit: true } => 1,
        ).and \
          measure_yabeda_histogram(Yabeda.sidekiq.job_runtime).with(
            { queue: "default", worker: "SampleComplexJob", implicit: true } => kind_of(Numeric),
          ).and \
            increment_yabeda_counter(Yabeda.test.whatever).with(
              { explicit: true, implicit: true } => 1,
            )
    end
  end

  describe "collection of Sidekiq statistics" do
    before do
      allow(Sidekiq::Stats).to receive(:new).and_return(
        OpenStruct.new(
          processes_size: 1,
          workers_size: 10,
          retry_size: 1,
          scheduled_size: 2,
          dead_size: 3,
          processed: 42,
          failed: 13,
          queues: { "default" => 5, "mailers" => 4 },
        ),
      )
      allow(Sidekiq::Queue).to receive(:all).and_return(
        [
          OpenStruct.new({ name: "default", latency: 0.5 }),
          OpenStruct.new({ name: "mailers", latency: 0 }),
        ],
      )
    end

    it "collects queue latencies" do
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.queue_latency).with(
          { queue: "default" } => 0.5,
          { queue: "mailers" } => 0.0,
        )
    end

    it "collects queue sizes" do
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.jobs_waiting_count).with(
          { queue: "default" } => 5,
          { queue: "mailers" } => 4,
        )
    end

    context "when show_queue_state is set to true" do
      # Pausing a queue is a Sidekiq Pro feature, so +paused?+ is stubbed in rather than
      # assumed to exist on the queue objects
      let(:running_queue) { pausable_queue("default", 0.5, paused: false) }
      let(:paused_queue) { pausable_queue("mailers", 0, paused: true) }

      around do |example|
        old_value = described_class.config.show_queue_state
        described_class.config.show_queue_state = true

        example.run

        described_class.config.show_queue_state = old_value
      end

      before do
        allow(Sidekiq::Queue).to receive(:all).and_return([running_queue, paused_queue])
      end

      it "segments queue latencies by queue state" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.queue_latency).with(
            { queue: "default", state: "unpaused" } => 0.5,
            { queue: "mailers", state: "paused" } => 0.0,
          )
      end

      it "segments queue sizes by queue state" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.jobs_waiting_count).with(
            { queue: "default", state: "unpaused" } => 5,
            { queue: "mailers", state: "paused" } => 4,
          )
      end

      it "resolves the state of every queue only once per collection cycle", :aggregate_failures do
        Yabeda.collect!

        expect(running_queue).to have_received(:paused?).once
        expect(paused_queue).to have_received(:paused?).once
      end

      # Queues can only be paused with Sidekiq Pro, so on OSS Sidekiq +paused?+ may be missing
      context "when queues do not support pausing" do
        before do
          allow(Sidekiq::Queue).to receive(:all).and_return(
            [OpenStruct.new({ name: "default", latency: 0.5 })],
          )
        end

        it "reports them as unpaused instead of failing the whole collection cycle" do
          expect { Yabeda.collect! }.to \
            update_yabeda_gauge(Yabeda.sidekiq.queue_latency).with(
              { queue: "default", state: "unpaused" } => 0.5,
            )
        end
      end

      # +Sidekiq::Stats#queues+ and +Sidekiq::Queue.all+ are two separate Redis reads,
      # so the queue list can miss a queue that the stats still know about
      context "when a queue is known to the stats but not to the queue list" do
        before { allow(Sidekiq::Queue).to receive(:all).and_return([paused_queue]) }

        it "falls back to unpaused instead of emitting a nil label" do
          expect { Yabeda.collect! }.to \
            update_yabeda_gauge(Yabeda.sidekiq.jobs_waiting_count).with(
              { queue: "mailers", state: "paused" } => 4,
              { queue: "default", state: "unpaused" } => 5,
            )
        end
      end
    end

    context "when show_queue_state is left disabled" do
      let(:queue) { pausable_queue("default", 0.5, paused: false) }

      before { allow(Sidekiq::Queue).to receive(:all).and_return([queue]) }

      it "does not ask queues for their state, keeping the extra Redis calls at zero" do
        Yabeda.collect!

        expect(queue).not_to have_received(:paused?)
      end
    end

    context "when show_queue_state is set to true" do
      # Pausing a queue is a Sidekiq Pro feature, so +paused?+ is stubbed in rather than
      # assumed to exist on the queue objects
      let(:running_queue) { pausable_queue("default", 0.5, paused: false) }
      let(:paused_queue) { pausable_queue("mailers", 0, paused: true) }

      around do |example|
        old_value = described_class.config.show_queue_state
        described_class.config.show_queue_state = true

        example.run

        described_class.config.show_queue_state = old_value
      end

      before do
        allow(Sidekiq::Queue).to receive(:all).and_return([running_queue, paused_queue])
      end

      it "reports the pause state of every queue" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.queue_paused).with(
            { queue: "default" } => 0,
            { queue: "mailers" } => 1,
          )
      end

      # Pause state deliberately does NOT become a label on these two: Prometheus gauges never
      # forget a label combination, so a queue that was paused once would keep exporting its
      # stale +paused+ series forever after being resumed
      it "leaves queue sizes unlabelled by pause state" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.jobs_waiting_count).with(
            { queue: "default" } => 5,
            { queue: "mailers" } => 4,
          )
      end

      it "leaves queue latencies unlabelled by pause state" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.queue_latency).with(
            { queue: "default" } => 0.5,
            { queue: "mailers" } => 0.0,
          )
      end

      it "asks every queue for its state only once per collection cycle", :aggregate_failures do
        Yabeda.collect!

        expect(running_queue).to have_received(:paused?).once
        expect(paused_queue).to have_received(:paused?).once
      end

      # Queues can only be paused with Sidekiq Pro, so on OSS Sidekiq +paused?+ may be missing
      context "when queues do not support pausing" do
        before do
          allow(Sidekiq::Queue).to receive(:all).and_return(
            [OpenStruct.new({ name: "default", latency: 0.5 })],
          )
        end

        it "reports them as not paused instead of failing the whole collection cycle" do
          expect { Yabeda.collect! }.to \
            update_yabeda_gauge(Yabeda.sidekiq.queue_paused).with({ queue: "default" } => 0)
        end
      end
    end

    context "when show_queue_state is left disabled" do
      let(:queue) { pausable_queue("default", 0.5, paused: false) }

      before { allow(Sidekiq::Queue).to receive(:all).and_return([queue]) }

      it "does not ask queues for their state, keeping the extra Redis calls at zero" do
        Yabeda.collect!

        expect(queue).not_to have_received(:paused?)
      end
    end

    it "collects named queues stats", :aggregate_failures do
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.jobs_retry_count).with(1).and \
          update_yabeda_gauge(Yabeda.sidekiq.jobs_dead_count).with(3).and \
            update_yabeda_gauge(Yabeda.sidekiq.jobs_scheduled_count).with(2)
    end

    it "measures maximum runtime of currently running jobs", sidekiq: :inline do
      workers = []
      workers.push(Thread.new { SampleLongRunningJob.perform_async })
      sleep 0.015 # Ruby can sleep less than requested
      workers.push(Thread.new { SampleLongRunningJob.perform_async })
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.running_job_runtime).with(
          { queue: "default", worker: "SampleLongRunningJob" } => (be >= 0.010),
        )

      sleep 0.015 # Ruby can sleep less than requested
      begin
        FailingActiveJob.perform_later
      rescue StandardError
        nil
      end

      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.running_job_runtime).with(
          { queue: "default", worker: "SampleLongRunningJob" } => (be >= 0.020),
        )

      # When all jobs are completed, metric should respond with zero
      workers.map(&:join)
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.running_job_runtime).with(
          { queue: "default", worker: "SampleLongRunningJob" } => 0.0,
        )
    end
  end

  # Stubbed +Sidekiq::Queue+ that knows whether it is paused, like the Sidekiq Pro one does.
  # Stubbing +paused?+ instead of putting it into the OpenStruct keeps the call counts assertable.
  def pausable_queue(name, latency, paused:)
    OpenStruct.new({ name: name, latency: latency }).tap do |queue|
      allow(queue).to receive(:paused?).and_return(paused)
    end
  end

  # Stubbed +Sidekiq::Queue+ that knows whether it is paused, like the Sidekiq Pro one does.
  # Stubbing +paused?+ instead of putting it into the OpenStruct keeps the call counts assertable.
  def pausable_queue(name, latency, paused:)
    OpenStruct.new({ name: name, latency: latency }).tap do |queue|
      allow(queue).to receive(:paused?).and_return(paused)
    end
  end

  def add_reroute_jobs_middleware
    ::Sidekiq.configure_server do |config|
      config.client_middleware do |chain|
        chain.insert_before Yabeda::Sidekiq::ClientMiddleware, ReRouteJobsMiddleware
      end
    end
  end

  def remove_reroute_jobs_middleware
    ::Sidekiq.configure_server do |config|
      config.client_middleware do |chain|
        chain.remove ReRouteJobsMiddleware
      end
    end
  end
end
