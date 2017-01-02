defmodule Freddy.ConnTest do
  use ExUnit.Case

  alias Freddy.Conn.Adapter.Sandbox.Connection

  test "restarts connection" do
    {:ok, conn} = Freddy.Conn.start_link(adapter: :sandbox)

    assert Freddy.Conn.status(conn) == :connected

    amqp_conn = Freddy.Conn.given_conn(conn)
    Connection.close(amqp_conn)

    :timer.sleep(100)

    assert Freddy.Conn.status(conn) == :connected

    Freddy.Conn.stop(conn)
  end

  test "open_channel" do
    {:ok, conn} = Freddy.Conn.start_link(adapter: :sandbox)
    result = Freddy.Conn.open_channel(conn)

    assert match?({:ok, %Freddy.Conn.Chan{}}, result)
  end

  test "request_channel" do
    {:ok, conn} = Freddy.Conn.start_link(adapter: :sandbox)
    Freddy.Conn.request_channel(conn)

    assert_receive {:CHANNEL, {:ok, %Freddy.Conn.Chan{}}, ^conn}
  end
end
