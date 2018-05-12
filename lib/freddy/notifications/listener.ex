defmodule Freddy.Notifications.Listener do
  @moduledoc """
  Freddy.Consumer special case. Listens for notifications from "freddy-topic" exchange.

  Like in `Freddy.Consumer`, you have to specify routing keys to bind to.

  Example:

      defmodule Notifications.Listener do
        use Freddy.Notifications.Listener

        @config [
          queue: [name: "myapp-notifications", opts: [auto_delete: true]],
          routing_keys: ["broadcast.*"]
        ]

        def start_link(conn, initial) do
          Freddy.Notifications.Listener.start_link(__MODULE__, conn, @config, initial)
        end
      end

  See also documentation for `Freddy.Consumer`
  """

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
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
          queue: Hare.Context.Action.DeclareQueue.config(),
          routing_keys: [String.t()],
          binds: [Keyword.t()]
        ]

  @compile {:inline, stop: 1, stop: 2}

  @doc """
  Start a `Freddy.Notifications.Listener` process linked to the current process.

  Arguments:

    * `mod` - the module that defines the server callbacks (like GenServer)
    * `connection` - the pid of a `Hare.Core.Conn` process
    * `config` - the configuration of the listener
    * `initial` - the value that will be given to `init/1`
    * `opts` - the GenServer options
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
