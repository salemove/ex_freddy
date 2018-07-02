defmodule Freddy.Notifications.Listener do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    warn? = Keyword.get(opts, :warn, true)

    quote location: :keep do
      if unquote(warn?) do
        IO.warn("#{unquote(__MODULE__)} will be removed in Freddy 1.0, use Freddy.Consumer instead")
      end

      use Freddy.Consumer
    end
  end

  @exchange [
    name: "freddy-topic",
    type: :topic
  ]

  @type connection :: Freddy.Consumer.connection()
  @type options :: GenServer.options()
  @type config :: [
          queue: Keyword.t(),
          routing_keys: [String.t()],
          binds: [Keyword.t()]
        ]

  @doc """
  Start a `Freddy.Notifications.Listener` process linked to the current process.

  Arguments:

    * `mod` - the module that defines the server callbacks (like `GenServer`)
    * `connection` - the pid of a `Freddy.Connection` process
    * `config` - the configuration of the listener
    * `initial` - the value that will be given to `init/1`
    * `opts` - the `GenServer` options
  """
  @spec start_link(module, connection, config, initial :: term, options) :: GenServer.on_start()
  def start_link(mod, conn, config, initial, opts \\ []) do
    config = Keyword.put(config, :exchange, @exchange)
    Freddy.Consumer.start_link(mod, conn, config, initial, opts)
  end

  defdelegate call(consumer, message, timeout \\ 5000), to: Freddy.Consumer
  defdelegate cast(consumer, message), to: Freddy.Consumer
  defdelegate stop(consumer, reason \\ :normal), to: Freddy.Consumer
  defdelegate ack(meta, opts \\ []), to: Freddy.Consumer
  defdelegate nack(meta, opts \\ []), to: Freddy.Consumer
  defdelegate reject(meta, opts \\ []), to: Freddy.Consumer
end
