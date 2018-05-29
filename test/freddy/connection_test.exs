defmodule Freddy.ConnectionTest do
  use ExUnit.Case

  alias Freddy.Connection

  # This test assumes that RabbitMQ server is running with default settings on localhost

  test "establishes connection to AMQP server" do
    assert {:ok, _pid} = Connection.start_link()
  end

  test "re-establishes connection if it's closed" do
    {:ok, pid} = Connection.start_link()

    assert {:ok, conn} = Connection.get_connection(pid)
    Connection.close(pid)

    assert {:ok, conn2} = Connection.get_connection(pid)
    assert conn.pid != conn2.pid
  end

  test "re-establishes connection if it's disrupted" do
    {:ok, pid} = Connection.start_link()
    assert {:ok, conn} = Connection.get_connection(pid)

    ref = Process.monitor(conn.pid)
    Process.exit(conn.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _, :killed}

    assert {:ok, conn2} = Connection.get_connection(pid)
    assert conn.pid != conn2.pid
  end

  test "re-establishes connection if server closed it" do
    {:ok, pid} = Connection.start_link()
    assert {:ok, conn} = Connection.get_connection(pid)

    ref = Process.monitor(conn.pid)
    Process.exit(conn.pid, {:shutdown, {:server_initiated_close, 320, 'Good bye'}})
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert {:ok, conn2} = Connection.get_connection(pid)
    assert conn.pid != conn2.pid
  end

  test "closes channel gracefully if calling process is stopped" do
    {:ok, pid} = Connection.start_link()

    parent = self()

    child =
      spawn_link(fn ->
        assert {:ok, chan} = Connection.open_channel(pid)

        send(parent, {:channel, chan})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:channel, chan}
    ref = Process.monitor(chan.pid)

    send(child, :stop)
    assert_receive {:DOWN, ^ref, :process, _, :normal}
  end

  test "process can be stopped by Process.exit" do
    {:ok, pid} = Connection.start_link()

    Process.unlink(pid)
    ref = Process.monitor(pid)
    Process.exit(pid, :restart)

    assert_receive {:DOWN, ^ref, :process, ^pid, :restart}
  end
end
