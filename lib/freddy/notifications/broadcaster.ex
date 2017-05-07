defmodule Freddy.Notifications.Broadcaster do
  @moduledoc """
  `Freddy.Publisher` special case.

  This module allows to publish messages to `freddy-topic` exchange.

  See documentation for `Freddy.Publisher`.
  """

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      use Freddy.Publisher

      defdelegate broadcast(broadcaster, routing_key, payload, opts \\ []), to: Freddy.Broadcaster
    end
  end

  @exchange_config [
    name: "freddy-topic",
    type: :topic
  ]

  @doc """
  Starts a `Freddy.Broadcaster` process linked to the current process.

  The process will be started by calling `init` with the given initial value.

  Arguments:

    * `mod` - the module that defines the server callbacks (like GenServer)
    * `conn` - the pid of a `Hare.Core.Conn` process
    * `initial` - the value that will be given to `init/1`
    * `opts` - the GenServer options
  """
  @spec start_link(module, GenServer.server, initial :: term, GenServer.options) :: GenServer.on_start
  def start_link(mod, conn, initial, opts \\ []) do
    Freddy.Publisher.start_link(mod, conn, [exchange: @exchange_config], initial, opts)
  end

  defdelegate stop(broadcaster, reason \\ :normal), to: GenServer

  @doc """
  Publish message with the given `routing_key` and `payload` to "freddy-topic" exchange.
  The message will be encoded to JSON before publication.

  Arguments:

    * `broadcaster` - the pid of a `Freddy.Broadcaster` process
    * `routing_key` - message routing key
    * `payload` - message payload
    * `opts` - AMQP `basic.publish` options (see `AMQP.Basic.publish/5` documentation)
  """
  def broadcast(broadcaster, routing_key, payload, opts \\ []) do
    Freddy.Publisher.publish(broadcaster, payload, routing_key, opts)
  end
end
