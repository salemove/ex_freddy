defmodule Freddy.Conn do
  @moduledoc """
  RabbitMQ connection establisher
  """

  alias Hare.Core.Conn

  alias Hare.Adapter.AMQP
  alias Hare.Adapter.Sandbox

  @adapters [
    amqp: AMQP,
    sandbox: Sandbox
  ]

  @default_adapter :amqp
  @default_backoff [1, 2, 3, 4, 5, 7, 10, 12, 15, 18]

  @compile {:inline, start_link: 1, start_link: 2, stop: 1, stop: 2}

  @type config        :: [config_option]
  @type config_option :: {:adapter, atom} |
                         {:backoff, [non_neg_integer]} |
                         {:history, GenServer.server} |
                         {:host, binary} |
                         {:port, pos_integer} |
                         {:username, binary} |
                         {:password, binary} |
                         {:virtual_host, binary} |
                         {:channel_max, non_neg_integer} |
                         {:frame_max, non_neg_integer} |
                         {:heartbeat, non_neg_integer} |
                         {:connection_timeout, timeout} |
                         {:ssl_options, Keyword.t | :none} |
                         {:client_properties, list} |
                         {:socket_options, list}

  @doc """
  Starts a `Hare.Core.Conn` process linked to the current process.

  It receives two arguments:

    * `config` - Connection configuration. See `Freddy.Conn.config_option` type for available options.
    * `opts` - GenServer options. See `GenServer.start_link/3` for more information.

  This function is used to start a `Hare.Core.Conn` on a supervision tree, and
  behaves like a GenServer.
  """
  @spec start_link(config, GenServer.options) :: GenServer.on_start
  def start_link(config \\ [], opts \\ []) do
    Conn.start_link(
      [config: connection_config(config),
       adapter: adapter(config),
       backoff: backoff(config)],
      opts
    )
  end

  defdelegate stop(conn, reason \\ :normal), to: Conn

  defp adapter(config) do
    adapter_name = Keyword.get(config, :adapter, @default_adapter)
    Keyword.fetch!(@adapters, adapter_name)
  end

  defp backoff(config) do
    Keyword.get(config, :backoff, @default_backoff)
  end

  defp connection_config(config) do
    Keyword.drop(config, [:adapte, :backoff])
  end
end
