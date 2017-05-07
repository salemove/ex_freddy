defmodule Freddy.ConsumerTest do
  use Freddy.ConnCase

  defmodule TestConsumer do
    use Freddy.Consumer

    @config [
      queue: [name: "test-consumer-queue", opts: [auto_delete: true]],
      exchange: [name: "freddy-topic", type: :topic],
      routing_keys: ~w(routing-key1 routing-key2)
    ]

    def start_link(conn, initial) do
      Freddy.Consumer.start_link(__MODULE__, conn, @config, initial)
    end

    def init(pid) do
      Process.flag(:trap_exit, true)
      send(pid, :init)

      {:ok, pid}
    end

    def handle_ready(meta, pid) do
      send(pid, {:ready, meta})

      {:noreply, pid}
    end

    def handle_message(payload, meta, pid) do
      send(pid, {:message, payload, meta})

      {:reply, :ack, pid}
    end

    def handle_error(error, message, meta, pid) do
      send(pid, {:error, error, message, meta})

      {:reply, :nack, pid}
    end

    def handle_info(message, pid) do
      send(pid, {:info, message})

      {:noreply, pid}
    end
  end

  describe "consumer initialization" do
    test "init/1 callback is called", %{conn: conn} do
      {:ok, consumer} = TestConsumer.start_link(conn, self())

      assert_receive :init

      tear_down(consumer)
    end

    test "handle_ready/2 callback is called when RabbitMQ registers consumer", %{conn: conn} do
      {:ok, consumer} = TestConsumer.start_link(conn, self())

      meta = %{consumer_tag: "foo"}
      rabbitmq_registered_consumer(consumer, meta)

      assert_receive {:ready, %{consumer_tag: "foo"} = _meta}

      tear_down(consumer)
    end

    test "bindings to the speficied exchange are set up", %{conn: conn, history: history} do
      {:ok, consumer} = TestConsumer.start_link(conn, self())
      rabbitmq_registered_consumer(consumer)

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

      tear_down(consumer)
    end

    defp rabbitmq_registered_consumer(consumer, meta \\ %{}) do
      send(consumer, {:consume_ok, meta})
    end
  end

  describe "consumer main loop" do
    test "handle_message/3 callback is called when RabbitMQ delivers valid JSON message", %{conn: conn} do
      payload = %{"key" => "value"}
      routing_key = "routing-key1"
      meta = %{routing_key: routing_key}

      consumer =
        conn
        |> start_consumer()
        |> deliver_message(Poison.encode!(payload), meta)

      assert_receive {:message, ^payload, %{routing_key: ^routing_key} = _meta}

      tear_down(consumer)
    end

    test "handle_error/4 callback is called when RabbitMQ delivers message with non-JSON payload", %{conn: conn} do
      payload = "invalid JSON"
      routing_key = "routing-key1"
      meta = %{routing_key: routing_key}

      consumer =
        conn
        |> start_consumer()
        |> deliver_message(payload, meta)

      assert_receive {:error, {:error, {:invalid, _token, _pos}}, ^payload, %{routing_key: ^routing_key} = _meta}

      tear_down(consumer)
    end

    test "handle_info/3 callback is called when arbitrary Erlang message is received", %{conn: conn} do
      consumer = start_consumer(conn)

      send(consumer, :some_message)
      assert_receive {:info, :some_message}

      tear_down(consumer)
    end

    defp start_consumer(conn) do
      {:ok, consumer} = TestConsumer.start_link(conn, self())
      send(consumer, {:consume_ok, %{}})

      consumer
    end

    def deliver_message(consumer, message, meta) do
      send(consumer, {:deliver, message, meta})

      consumer
    end
  end

  defp tear_down(consumer) do
    Freddy.Consumer.stop(consumer)
  end
end
