defmodule Freddy.Integration.ConsumerTest do
  use Freddy.IntegrationCase

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
    def handle_disconnected(reason, pid) do
      send(pid, {:disconnected, reason})
      {:noreply, pid}
    end

    @impl true
    def handle_message(payload, meta, pid) do
      send(pid, {:message, payload, meta})

      {:reply, :ack, pid}
    end

    @impl true
    def handle_call(:call, _from, pid) do
      {:reply, :response, pid}
    end

    @impl true
    def handle_cast(:cast, pid) do
      send(pid, :cast)
      {:noreply, pid}
    end

    @impl true
    def handle_info(:info, pid) do
      send(pid, :info)
      {:noreply, pid}
    end

    @impl true
    def terminate(reason, pid) do
      send(pid, {:terminate, reason})
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

  describe "consumer initialization" do
    test "init/1 callback is called", %{connection: connection} do
      {:ok, _consumer} = TestConsumer.start_link(connection, self())

      assert_receive :init
    end

    test "handle_connected/2 callback is called when RabbitMQ channel is opened", %{
      connection: connection
    } do
      {:ok, _consumer} = TestConsumer.start_link(connection, self())

      assert_receive {:connected, %{queue: _, exchange: _}}
    end

    test "handle_ready/2 callback is called when RabbitMQ registers consumer", %{
      connection: connection
    } do
      {:ok, _consumer} = TestConsumer.start_link(connection, self())

      assert_receive {:ready, %{consumer_tag: _tag}}
    end
  end

  describe "consumer main loop" do
    setup context do
      {:ok, consumer} = TestConsumer.start_link(context[:connection], self())
      assert_receive :init
      assert_receive {:ready, _}

      {:ok, Map.put(context, :consumer, consumer)}
    end

    test "handle_message/3 callback is called when RabbitMQ delivers valid JSON message", %{
      connection: connection
    } do
      payload = %{"key" => "value"}
      routing_key = "routing-key1"

      {:ok, publisher} = TestPublisher.start_link(connection)
      Freddy.Publisher.publish(publisher, payload, routing_key)

      assert_receive {:message, ^payload, %{routing_key: ^routing_key} = _meta}
    end

    test "binds only to specified routing keys", %{connection: connection} do
      routing_key = "unknown-routing-key"

      {:ok, publisher} = TestPublisher.start_link(connection)
      Freddy.Publisher.publish(publisher, %{}, routing_key)

      refute_receive {:message, _, %{routing_key: ^routing_key}}
    end

    test "handle_disconnected/2 callback is called when connection is disrupted", %{
      connection: connection
    } do
      assert {:ok, conn} = Freddy.Connection.get_connection(connection)

      ref = Process.monitor(conn)
      Process.exit(conn, {:shutdown, {:server_initiated_close, 320, 'Good bye'}})
      assert_receive {:DOWN, ^ref, :process, _, _}

      assert_receive {:disconnected, :shutdown}
      refute_receive :init
      assert_receive {:ready, _}
    end

    test "handle_call/3 is called on Freddy.Consumer.call", %{consumer: consumer} do
      assert :response = Freddy.Consumer.call(consumer, :call)
    end

    test "handle_cast/2 is called on Freddy.Consumer.cast", %{consumer: consumer} do
      assert :ok = Freddy.Consumer.cast(consumer, :cast)
      _ = :sys.get_state(consumer)
      assert_receive :cast
    end

    test "handle_info/2 is called on other messages", %{consumer: consumer} do
      send(consumer, :info)
      _ = :sys.get_state(consumer)
      assert_receive :info
    end

    test "terminate/2 is called when the process stops", %{consumer: consumer} do
      Freddy.Consumer.stop(consumer, :normal)
      assert_receive {:terminate, :normal}
    end
  end
end
