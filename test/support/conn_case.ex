defmodule Freddy.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a RabbitMQ connection.
  """

  use ExUnit.CaseTemplate

  alias Freddy.Conn
  alias Hare.Adapter.Sandbox, as: Adapter

  using do
    quote do
      alias Hare.Adapter.Sandbox, as: Adapter
    end
  end

  setup _tags do
    {:ok, history} = Adapter.Backdoor.start_history()
    {:ok, conn} = Conn.start_link(
      history: history,
      adapter: :sandbox
    )

    {:ok, conn: conn, history: history}
  end
end
