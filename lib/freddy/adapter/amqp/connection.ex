defmodule Freddy.Adapter.AMQP.Connection do
  @moduledoc false

  @default_options [
    heartbeat: 10,
    connection_timeout: 5000
  ]

  def open(options)

  def open(options) when is_list(options) do
    @default_options
    |> Keyword.merge(options)
    |> do_open()
  end

  def open(uri) when is_binary(uri) do
    do_open(uri)
  end

  defp do_open(options_or_uri) do
    case AMQP.Connection.open(options_or_uri) do
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
