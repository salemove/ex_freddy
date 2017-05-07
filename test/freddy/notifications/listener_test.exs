defmodule Freddy.Notifications.ListenerTest do
  use Freddy.ConnCase

  defmodule TestListener do
    use Freddy.Notifications.Listener

    @config [
      queue: [name: "test-consumer-queue", opts: [auto_delete: true]],
      routing_keys: ~w(routing-key1 routing-key2)
    ]

    def start_link(conn, initial) do
      Freddy.Notifications.Listener.start_link(__MODULE__, conn, @config, initial)
    end

    def handle_ready(meta, pid) do
      send(pid, {:ready, meta})

      {:noreply, pid}
    end

    def handle_message(_payload, _meta, state) do
      {:reply, :ack, state}
    end
  end

  test "bindings to 'freddy-topic' exchange are set up", %{conn: conn, history: history} do
    {:ok, consumer} = TestListener.start_link(conn, self())
    send(consumer, {:consume_ok, %{}})

    assert_receive {:ready, %{queue: queue, exchange: exchange} = _meta}
    assert %{chan: chan, name: "test-consumer-queue"} = queue
    assert %{chan: ^chan, name: "freddy-topic"} = exchange

    assert [{:bind,
              [chan, "test-consumer-queue", "freddy-topic", [routing_key: "routing-key1"]],
              :ok},
            {:bind,
              [chan, "test-consumer-queue", "freddy-topic", [routing_key: "routing-key2"]],
              :ok},
            {:consume,
              [chan, "test-consumer-queue", ^consumer, _opts],
              {:ok, _consumer_tag}}] = Adapter.Backdoor.last_events(history, 3)

    Freddy.Notifications.Listener.stop(consumer)
  end
end
