defmodule Freddy.ConnectionCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require fake RabbitMQ connection.
  """

  use ExUnit.CaseTemplate

  alias Freddy.Connection
  alias Freddy.Adapter.Sandbox

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  setup _tags do
    {:ok, connection} = Connection.start_link(adapter: :sandbox)
    {:ok, connection: connection}
  end

  def history(conn, events \\ :all, flush? \\ false) do
    with {:ok, pid} <- Connection.get_connection(conn) do
      Sandbox.history(pid, events, flush?)
    end
  end
end
