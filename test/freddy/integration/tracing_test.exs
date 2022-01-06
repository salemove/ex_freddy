defmodule Freddy.Integration.TracingTest do
  use Freddy.IntegrationCase

  require OpenTelemetry.Tracer
  require Record

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/otel_span.hrl") do
    Record.defrecord(name, spec)
  end

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry_api/include/opentelemetry.hrl") do
    Record.defrecord(name, spec)
  end

  defmodule TestConsumer do
    use Freddy.Consumer

    @config [
      queue: [name: "freddy-test-consumer-queue", opts: [auto_delete: true]],
      exchange: [name: "freddy-test-topic-exchange", type: :topic, opts: [auto_delete: true]],
      routing_keys: ~w(routing-key1 routing-key2)
    ]

    def start_link(conn, initial) do
      Freddy.Consumer.start_link(__MODULE__, conn, @config, initial)
    end

    @impl true
    def init(pid) do
      Process.flag(:trap_exit, true)
      send(pid, :init)

      {:ok, pid}
    end

    @impl true
    def handle_connected(meta, pid) do
      send(pid, {:connected, meta})
      {:noreply, pid}
    end

    @impl true
    def handle_ready(meta, pid) do
      send(pid, {:ready, meta})

      {:noreply, pid}
    end

    @impl true
    def handle_message(payload, meta, pid) do
      send(pid, {:message, payload, meta})

      if payload["raise"] do
        raise payload["raise"]
      end

      {:reply, :ack, pid}
    end
  end

  defmodule TestPublisher do
    use Freddy.Publisher

    @config [
      exchange: [name: "freddy-test-topic-exchange", type: :topic, opts: [auto_delete: true]]
    ]

    def start_link(conn) do
      Freddy.Publisher.start_link(__MODULE__, conn, @config, nil)
    end
  end

  setup context do
    :application.stop(:opentelemetry)
    :application.set_env(:opentelemetry, :tracer, :otel_tracer_default)

    :application.set_env(:opentelemetry, :processors, [
      {:otel_batch_processor, %{scheduled_delay_ms: 1, exporter: {:otel_exporter_pid, self()}}}
    ])

    :application.start(:opentelemetry)

    {:ok, _consumer} = TestConsumer.start_link(context[:connection], self())
    assert_receive :init
    assert_receive {:connected, _}
    assert_receive {:ready, _}

    :ok
  end

  test "links producer and consumer traces together", %{connection: connection} do
    payload = %{"key" => "value"}
    routing_key = "routing-key1"

    {:ok, publisher} = TestPublisher.start_link(connection)
    Freddy.Publisher.publish(publisher, payload, routing_key)

    assert_receive {:message, ^payload, %{routing_key: ^routing_key} = _meta}

    # Send: Starts a new trace because there are no existing trace
    assert_receive {:span,
                    span(
                      name: "freddy-test-topic-exchange.routing-key1 send",
                      kind: :producer,
                      status: :undefined,
                      trace_id: sender_trace_id,
                      parent_span_id: :undefined,
                      span_id: sender_span_id,
                      attributes: attributes
                    )}

    assert %{
             "messaging.destination": "freddy-test-topic-exchange",
             "messaging.destination_kind": "topic",
             "messaging.rabbitmq_routing_key": "routing-key1",
             "messaging.system": "rabbitmq"
           } = :otel_attributes.map(attributes)

    # Process: starts a new trace and but uses `links` to link them together.
    assert_receive {:span,
                    span(
                      name: "freddy-test-topic-exchange.routing-key1 process",
                      kind: :consumer,
                      status: :undefined,
                      links: links,
                      attributes: attributes
                    )}

    assert [link(trace_id: ^sender_trace_id, span_id: ^sender_span_id)] = :otel_links.list(links)

    assert %{
             "messaging.destination": "freddy-test-topic-exchange",
             "messaging.destination_kind": "topic",
             "messaging.freddy.worker": "Elixir.Freddy.Integration.TracingTest.TestConsumer",
             "messaging.operation": "process",
             "messaging.rabbitmq_routing_key": "routing-key1",
             "messaging.system": "rabbitmq"
           } = :otel_attributes.map(attributes)
  end

  test "consumer does not create a link when no existing trace", %{connection: connection} do
    payload = %{"key" => "value"}
    routing_key = "routing-key1"

    {:ok, publisher} = TestPublisher.start_link(connection)
    Freddy.Publisher.publish(publisher, payload, routing_key, disable_trace_propagation: true)

    assert_receive {:message, ^payload, %{routing_key: ^routing_key} = _meta}

    assert_receive {:span,
                    span(
                      name: "freddy-test-topic-exchange.routing-key1 process",
                      kind: :consumer,
                      status: :undefined,
                      parent_span_id: :undefined,
                      links: links,
                      attributes: _attributes
                    )}

    assert [] = :otel_links.list(links)
  end

  test "producer uses existing trace when present", %{connection: connection} do
    payload = %{"key" => "value"}
    routing_key = "routing-key1"

    {:ok, publisher} = TestPublisher.start_link(connection)

    OpenTelemetry.Tracer.with_span "test span" do
      Freddy.Publisher.publish(publisher, payload, routing_key)
    end

    assert_receive {:message, ^payload, %{routing_key: ^routing_key} = _meta}

    # We manually started a new trace
    assert_receive {:span, span(name: "test span", trace_id: trace_id, span_id: root_span_id)}

    # Send: Re-uses the existing trace
    assert_receive {:span,
                    span(
                      name: "freddy-test-topic-exchange.routing-key1 send",
                      kind: :producer,
                      status: :undefined,
                      trace_id: ^trace_id,
                      parent_span_id: ^root_span_id
                    )}
  end

  test "consumer marks span as errored on exception", %{connection: connection} do
    Process.flag(:trap_exit, true)

    payload = %{"raise" => "some-error"}
    routing_key = "routing-key1"

    {:ok, publisher} = TestPublisher.start_link(connection)

    Freddy.Publisher.publish(publisher, payload, routing_key)

    assert_receive {:message, ^payload, %{routing_key: ^routing_key} = _meta}

    expected_status = OpenTelemetry.status(:error, "")

    assert_receive {:span,
                    span(
                      name: "freddy-test-topic-exchange.routing-key1 process",
                      kind: :consumer,
                      status: ^expected_status,
                      events: events
                    )}

    [event(name: "exception", attributes: event_attributes)] = :otel_events.list(events)

    assert %{
             "exception.type" => "Elixir.RuntimeError",
             "exception.message" => "some-error",
             "exception.stacktrace" => _stacktrace
           } = :otel_attributes.map(event_attributes)
  end
end
