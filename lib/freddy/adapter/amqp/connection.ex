defmodule Freddy.Adapter.AMQP.Connection do
  @moduledoc false

  def open(options) do
    case AMQP.Connection.open(options) do
      {:ok, %{pid: pid}} -> {:ok, pid}
      {:error, _reason} = result -> result
    end
  end

  def close(connection) do
    case :amqp_connection.close(connection) do
      :ok -> :ok
      error -> {:error, error}
    end
  end

  def link(connection) do
    Process.link(connection)
    :ok
  end
end
