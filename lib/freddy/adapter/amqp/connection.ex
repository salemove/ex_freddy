defmodule Freddy.Adapter.AMQP.Connection do
  @moduledoc false

  import Freddy.Adapter.AMQP.Core

  def open(options)

  def open(options) when is_list(options) do
    amqp_params =
      amqp_params_network(
        username: Keyword.get(options, :username, "guest"),
        password: Keyword.get(options, :password, "guest"),
        virtual_host: Keyword.get(options, :virtual_host, "/"),
        host: Keyword.get(options, :host, ~c"localhost") |> to_charlist(),
        port: Keyword.get(options, :port, :undefined),
        channel_max: Keyword.get(options, :channel_max, 0),
        frame_max: Keyword.get(options, :frame_max, 0),
        heartbeat: Keyword.get(options, :heartbeat, 10),
        connection_timeout: Keyword.get(options, :connection_timeout, 5000),
        ssl_options: Keyword.get(options, :ssl_options, :none) |> normalize_ssl_options(),
        client_properties: Keyword.get(options, :client_properties, []),
        socket_options: Keyword.get(options, :socket_options, []),
        auth_mechanisms:
          Keyword.get(options, :auth_mechanisms, [
            &:amqp_auth_mechanisms.plain/3,
            &:amqp_auth_mechanisms.amqplain/3
          ])
      )

    do_open(amqp_params)
  end

  defp do_open(amqp_params) do
    :amqp_connection.start(amqp_params)
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

  defp normalize_ssl_options(options) when is_list(options) do
    for {k, v} <- options do
      if k in [:cacertfile, :certfile, :keyfile] do
        {k, to_charlist(v)}
      else
        {k, v}
      end
    end
  end

  defp normalize_ssl_options(options) do
    options
  end
end
