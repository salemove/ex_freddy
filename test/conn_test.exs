defmodule Freddy.ConnTest do
  use ExUnit.Case

  test "restarts connection" do
    {:ok, conn} = Freddy.Conn.start_link()

    assert Freddy.Conn.status(conn) == :connected

    amqp_conn = Freddy.Conn.given_conn(conn)
    AMQP.Connection.close(amqp_conn)

    :timer.sleep(100)

    assert Freddy.Conn.status(conn) == :connected

    Freddy.Conn.stop(conn)
  end
end
