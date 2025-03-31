defmodule Freddy.Integration.ConnectionTest do
  use ExUnit.Case

  alias Freddy.Connection
  alias Freddy.Core.Channel

  import Freddy.Adapter.AMQP.Core

  # This test assumes that RabbitMQ server is running with default settings on localhost

  test "establishes connection to AMQP server" do
    assert {:ok, _pid} = Connection.start_link()
  end

  test "re-establishes connection if it's closed" do
    {:ok, pid} = Connection.start_link()

    assert {:ok, conn} = Connection.get_connection(pid)
    Connection.close(pid)

    assert {:ok, conn2} = Connection.get_connection(pid)
    assert conn != conn2
  end

  test "re-establishes connection if it's disrupted" do
    {:ok, pid} = Connection.start_link()
    assert {:ok, conn} = Connection.get_connection(pid)

    ref = Process.monitor(conn)
    Process.exit(conn, :kill)
    assert_receive {:DOWN, ^ref, :process, _, :killed}

    assert {:ok, conn2} = Connection.get_connection(pid)
    assert conn != conn2
  end

  @tag capture_log: true
  test "re-establishes connection if server closed it" do
    {:ok, pid} = Connection.start_link()
    assert {:ok, conn} = Connection.get_connection(pid)

    ref = Process.monitor(conn)
    :amqp_gen_connection.server_close(conn, {:"connection.close", ~c"Good bye", 302, 0, 0})
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert {:ok, conn2} = Connection.get_connection(pid)
    assert conn != conn2
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
    ref = Channel.monitor(chan)

    send(child, :stop)
    assert_receive {:DOWN, ^ref, :process, _, :normal}
  end

  @tag capture_log: true
  test "process can be stopped by Process.exit" do
    {:ok, pid} = Connection.start_link()

    Process.unlink(pid)
    ref = Process.monitor(pid)
    Process.exit(pid, :restart)

    assert_receive {:DOWN, ^ref, :process, ^pid, :restart}
  end

  test "establishes connection to secondary server if primary server is unavailable" do
    {:ok, pid} =
      Connection.start_link([
        [host: "127.0.0.2", connection_timeout: 500, port: 6389],
        [host: "127.0.0.1"]
      ])

    assert {:ok, conn} = Connection.get_connection(pid)
    assert is_pid(conn)
    assert [amqp_params: params] = :amqp_connection.info(conn, [:amqp_params])
    amqp_params_network(host: host) = params
    assert host == '127.0.0.1'
  end
end
