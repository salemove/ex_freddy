defmodule Freddy.Integration.Notifications.BroadcasterTest do
  use Freddy.IntegrationCase

  defmodule TestBroadcaster do
    use Freddy.Notifications.Broadcaster, warn: false

    def start_link(conn) do
      Freddy.Notifications.Broadcaster.start_link(__MODULE__, conn, nil)
    end
  end

  defmodule TestListener do
    use Freddy.Consumer

    @config [
      queue: [opts: [auto_delete: true]],
      exchange: [name: "freddy-topic", type: :topic],
      routing_keys: ["freddy-test"]
    ]

    def start_link(conn, pid) do
      Freddy.Consumer.start_link(__MODULE__, conn, @config, pid)
    end

    @impl true
    def handle_ready(_meta, pid) do
      send(pid, :consumer_ready)
      {:noreply, pid}
    end

    @impl true
    def handle_message(message, _meta, pid) do
      send(pid, {:message_received, message})
      {:reply, :ack, pid}
    end
  end

  # we're dealing with real RabbitMQ instance which may add latency
  @assert_receive_interval 500

  test "publishes message into freddy-topic exchange", %{connection: connection} do
    {:ok, broadcaster} = TestBroadcaster.start_link(connection)
    {:ok, _consumer} = TestListener.start_link(connection, self())

    assert_receive :consumer_ready, @assert_receive_interval

    payload = %{"key" => "value"}
    TestBroadcaster.broadcast(broadcaster, "freddy-test", payload)

    assert_receive {:message_received, ^payload}
  end
end
