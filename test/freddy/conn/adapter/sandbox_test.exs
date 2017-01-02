defmodule Freddy.Conn.Adapter.SandboxTest do
  use ExUnit.Case

  alias Freddy.Conn.Adapter.Sandbox.History
  alias Freddy.Conn.Adapter.Sandbox, as: Adapter

  test "open_connection, monitor_connection, close_connection" do
    {:ok, history} = History.start_link()
    {:ok, conn} = Adapter.open_connection(history: history)
    pid = conn.pid
    ref = Adapter.monitor_connection(conn)

    assert Process.alive?(pid)

    Adapter.close_connection(conn)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    flush(history)

    assert_receive {:connect, ^pid}
    assert_receive {:monitor_connection, {:from, _}}
    assert_receive {:close_connection, _}
    assert_receive {:connection_terminate, :normal}
  end

  test "connection lost" do
    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"
    Adapter.monitor_connection(conn)

    Adapter.disconnect(conn)
    :timer.sleep(100)

    refute Process.alive?(conn.pid), "Connection should have been killed"
    assert_receive {:DOWN, _ref, :process, _pid, :socket_closed_unexpectedly}
  end

  test "open_channel, close_channel, monitor_channel" do
    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"

    {:ok, chan} = Adapter.open_channel(conn)
    assert Process.alive?(chan.pid), "Channel process should have spawned"

    ref = Adapter.monitor_channel(chan)

    Adapter.close_channel(chan)

    assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    :timer.sleep(100)

    refute Process.alive?(chan.pid), "Channel process should have died"
    assert Process.alive?(conn.pid), "Closing channel should not affect connection"
  end

  test "close channel abnormally" do
    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"

    {:ok, chan} = Adapter.open_channel(conn)
    assert Process.alive?(chan.pid), "Channel process should have spawned"

    Process.exit(chan.pid, :kill)
    :timer.sleep(100)

    refute Process.alive?(chan.pid), "Channel process should have been killed"
    refute Process.alive?(conn.pid), "Killed channel should have killed connection"
  end

  test "close connection abnormally" do
    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"

    {:ok, chan} = Adapter.open_channel(conn)
    assert Process.alive?(chan.pid), "Channel process should have spawned"

    Process.exit(chan.pid, :kill)
    :timer.sleep(100)

    refute Process.alive?(conn.pid), "Connection should have been killed"
    refute Process.alive?(chan.pid), "Killed connection should have killed channel process"
  end

  test "close connection normally" do
    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"

    {:ok, chan} = Adapter.open_channel(conn)
    assert Process.alive?(chan.pid), "Channel process should have spawned"

    ref = Adapter.monitor_channel(chan)

    Adapter.close_connection(conn)
    :timer.sleep(100)

    assert_receive {:DOWN, ^ref, :process, _from, :normal}
    refute Process.alive?(chan.pid), "Channel should have been closed with connection"
  end

  test "register_return_handler, unregister_return_handler" do
    import AMQP.Core

    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"

    {:ok, chan} = Adapter.open_channel(conn)
    assert Process.alive?(chan.pid), "Channel process should have spawned"

    :ok = Adapter.register_return_handler(chan, self())

    # publish message to a queue that nobody listens to
    Adapter.publish(chan, "", "unknown-queue", "payload")
    assert_receive { basic_return(reply_text: "NO_ROUTE"), {:amqp_msg, p_basic(), "payload"} }

    :ok = Adapter.unregister_return_handler(chan)

    Adapter.publish(chan, "", "unknown-queue", "payload")
    refute_receive { basic_return(), _ }
  end

  test "declare_queue" do
    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"

    {:ok, chan} = Adapter.open_channel(conn)
    assert Process.alive?(chan.pid), "Channel process should have spawned"

    {:ok, %{queue: name}} = Adapter.declare_queue(chan, "")
    refute name == "", "Server named queue should have been created"

    given_name = "queue"
    {:ok, %{queue: name}} = Adapter.declare_queue(chan, given_name)
    assert name == given_name, "Queue with given name should have been created"
  end

  test "consume/publish" do
    {:ok, conn} = Adapter.open_connection()
    assert Process.alive?(conn.pid), "Connection process should have spawned"

    {:ok, chan} = Adapter.open_channel(conn)
    assert Process.alive?(chan.pid), "Channel process should have spawned"

    queue = "queue"
    payload = "payload"

    {:ok, consumer_tag} = Adapter.consume(chan, queue)
    assert_receive {:basic_consume_ok, %{consumer_tag: ^consumer_tag}}

    Adapter.publish(chan, "", queue, payload)
    assert_receive {:basic_deliver, "payload", _properties = %{}}
  end

  defp flush(history) do
    events = History.events(history)
    Enum.each(events, fn event -> send(self(), event) end)
  end
end
