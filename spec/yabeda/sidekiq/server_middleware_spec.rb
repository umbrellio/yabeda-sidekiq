# frozen_string_literal: true

RSpec.describe Yabeda::Sidekiq::ServerMiddleware, sidekiq: :inline do
  let(:events) { [] }
  let!(:subscription) do
    ActiveSupport::Notifications.subscribe("perform.sidekiq_job") { |event| events << event }
  end

  after { ActiveSupport::Notifications.unsubscribe(subscription) }

  it "wraps successful job execution into the event with worker labels" do
    SamplePlainJob.perform_async

    expect(events.size).to eq(1)

    event = events.first
    expect(event.payload).to include(worker: "SamplePlainJob", queue: "default")
    expect(event.duration).to be >= 0
    expect(event.allocations).to be > 0
  end

  it "records the exception into the event payload and re-raises it" do
    expect { FailingPlainJob.perform_async }.to raise_error(FailingPlainJob::SpecialError)

    expect(events.size).to eq(1)
    expect(events.first.payload[:exception]).to eq(["FailingPlainJob::SpecialError", "Badaboom"])
  end

  describe "allocation metrics" do
    let(:labels) { { queue: "default", worker: "SamplePlainJob" } }

    it "increments allocations_total" do
      expect { SamplePlainJob.perform_async }.to \
        increment_yabeda_counter(Yabeda.sidekiq.allocations_total).with_tags(labels)
    end

    it "does not increment malloc_increase_bytes without the Event patch" do
      expect { SamplePlainJob.perform_async }.not_to \
        increment_yabeda_counter(Yabeda.sidekiq.malloc_increase_bytes)
    end

    context "when the Event is patched with malloc_increase_bytes" do
      before do
        # Emulates the ActiveSupport::Notifications::Event patch from umbrellio-utils
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(ActiveSupport::Notifications::Event)
          .to receive(:malloc_increase_bytes).and_return(2048)
        # rubocop:enable RSpec/AnyInstance
      end

      it "increments malloc_increase_bytes" do
        expect { SamplePlainJob.perform_async }.to \
          increment_yabeda_counter(Yabeda.sidekiq.malloc_increase_bytes).with(labels => 2048)
      end
    end
  end
end
