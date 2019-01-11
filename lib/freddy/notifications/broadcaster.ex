defmodule Freddy.Notifications.Broadcaster do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    warn? = Keyword.get(opts, :warn, true)

    quote location: :keep do
      if unquote(warn?) do
        IO.warn(
          "#{unquote(__MODULE__)} will be removed in Freddy 1.0, use Freddy.Publisher instead"
        )
      end

      use Freddy.Publisher

      defdelegate broadcast(broadcaster, routing_key, payload, opts \\ []),
        to: Freddy.Notifications.Broadcaster
    end
  end

  @exchange_config [
    name: "freddy-topic",
    type: :topic
  ]

  @doc """
  Starts a `Freddy.Broadcaster` process linked to the current process.

  The process will be started by calling `init/1` with the given initial value.

  Arguments:

    * `mod` - the module that defines the server callbacks (like `GenServer`)
    * `conn` - the pid of a `Freddy.Connection` process
    * `initial` - the value that will be given to `init/1`
    * `opts` - the `GenServer` options
  """
  @spec start_link(module, GenServer.server(), initial :: term, GenServer.options()) ::
          GenServer.on_start()
  def start_link(mod, conn, initial, opts \\ []) do
    Freddy.Publisher.start_link(mod, conn, [exchange: @exchange_config], initial, opts)
  end

  @doc """
  Publish message with the given `routing_key` and `payload` to `"freddy-topic"` exchange.
  The message will be encoded to JSON before publication.

  Arguments:

    * `broadcaster` - the pid of a `Freddy.Broadcaster` process
    * `routing_key` - message routing key
    * `payload` - message payload
    * `opts` - Publisher options (see `Freddy.Publisher.publish/4` documentation)
  """
  def broadcast(broadcaster, routing_key, payload, opts \\ []) do
    Freddy.Publisher.publish(broadcaster, payload, routing_key, opts)
  end

  defdelegate call(consumer, message, timeout \\ 5000), to: Freddy.Publisher
  defdelegate cast(consumer, message), to: Freddy.Publisher
  defdelegate stop(consumer, reason \\ :normal), to: Freddy.Publisher
end
