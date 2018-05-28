defmodule Freddy.ConnectionCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a RabbitMQ connection.
  """

  use ExUnit.CaseTemplate

  alias Freddy.Connection

  setup _tags do
    {:ok, connection} = Connection.start_link()
    {:ok, connection: connection}
  end
end
