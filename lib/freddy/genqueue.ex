defmodule Freddy.GenQueue do
  @moduledoc """
  A behaviour module for implementing AMQP Producers/Consumers.
  """

  @type state   :: any
  @type options :: Keyword.t
  @type on_callback :: {:noreply, state}
                     | {:noreply, state, timeout | :hibernate}
                     | {:connect, info :: any, state}
                     | {:disconnect, reason :: any, state}
                     | {:stop, reason :: any, state}

  @doc """
  Called when GenQueue process is first started. `start_link/2` will block until it returns.
  """
  @callback init_worker(state, options) :: state

  @doc """
  Called when GenQueue successfully obtains Channel from AMQP Connection.

  This callback must return same value as `Connection.handle_info/2` callback.

  Returns `{:noreply, state}` by default.
  """
  @callback handle_connect(state) :: on_callback

  @doc """
  Called when AMQP Connection is lost or Channel process went down.

  This callback must return same value as `Connection.handle_info/2` callback.

  Returns `{:disconnect, reason, state}` by default.
  """
  @callback handle_disconnect(reason :: any, state) :: on_callback

  defmacro __using__(properties \\ []) do
    quote bind_quoted: [properties: properties], location: :keep do
      use Connection
      @behaviour Freddy.GenQueue

      defmodule State do
        use Freddy.GenQueue.State, properties
      end

      alias __MODULE__.State, as: State

      @type connection :: Freddy.Conn.connection
      @type server     :: GenServer.server
      @type options    :: [option]
      @type option     :: {atom, term}
      @type status     :: :not_connected
                        | :connecting
                        | :connected
      @type state      :: State.t

      @doc """
      Start Producer/Consumer and link it to the current process.
      """
      @spec start_link(connection, options) :: GenServer.on_start
      def start_link(conn, opts \\ []),
        do: Connection.start_link(__MODULE__, [conn, opts])

      @doc """
      Start Producer/Consumer without linking it to the current process.
      """
      @spec start(connection, options) :: GenServer.on_start
      def start(conn, opts \\ []),
        do: Connection.start(__MODULE__, [conn, opts])

      @doc """
      Close existing channel and stop GenQueue process.
      """
      @spec stop(server) :: :ok
      def stop(server),
        do: Connection.call(server, {:close, :normal})

      @doc """
      Return current status of GenQueue process.
      """
      @spec status(server) :: status
      def status(server),
        do: Connection.call(server, :status)

      @doc """
      Block calling process until GenQueue process will obtain Channel from AMQP Connection process.
      """
      @spec await_connection(server, timeout) ::
        {:ok, :connected} | {:error, reason :: term}
      def await_connection(server, timeout \\ :infinity) do
        notify_on_connect(server, self())

        receive do
          {:GENQUEUE_CONNECTION, result, _from} -> result
        after timeout ->
          {:error, :timeout}
        end
      end

      @doc """
      Subscribe calling process for GenQueue connection status change event.
      Once GenQueue process obtains channel, it will send `{:GENQUEUE_CONNECTION, {:ok, channel}, pid}`
      to subscribers. If GenQueue process can't obtain channel from connection it will send
      `{:GENQUEUE_CONNECTION, {:error, reason}, pid}`.

      This mechanism can be used for asynchronous initialization of dependant producers/consumers.
      """
      @spec notify_on_connect(server, listener :: pid) :: :ok
      def notify_on_connect(server, listener \\ nil),
        do: Connection.cast(server, {:notify_on_connect, listener || self()})

      @doc """
      Returns true if GenQueue obtained AMQP channel.
      """
      @spec connected?(server) :: boolean
      def connected?(server),
        do: status(server) == :connected

      # GenQueue overridable callbacks
      @doc false
      def init_worker(state, _opts),
        do: state

      @doc false
      def handle_connect(state),
        do: {:noreply, state}

      # Will disconnect by default
      @doc false
      def handle_disconnect(reason, state),
        do: {:disconnect, reason, state}

      @doc false
      def terminate(_reason, state),
        do: State.disconnect(state)

      defoverridable [init_worker: 2,
        handle_connect: 1, handle_disconnect: 2, terminate: 2]

      # GenServer/Connection callbacks

      @doc false
      def init([conn, opts]) do
        state =
          State.new(conn, opts)
          |> init_worker(opts)

        {:connect, :init, state}
      end

      @doc false
      def connect(info, state) do
        new_state = State.connect(state, info)
        {:ok, new_state}
      end

      @doc false
      def disconnect(reason, state),
        do: {:stop, reason, state}

      @doc false
      def handle_call({:close, reason}, _from, state),
        do: {:disconnect, reason, :ok, state}

      @doc false
      def handle_call(:status, _from, state),
        do: {:reply, state.status, state}

      @doc false
      def handle_cast({:notify_on_connect, from}, state),
        do: {:noreply, State.notify_on_connect(state, from)}

      @doc false
      def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
        # Stop worker if Freddy.conn went down
        if State.down?(state, ref) do
          {:disconnect, :disconnected, state}
        else
          handle_disconnect(reason, state)
        end
      end

      @doc false
      def handle_info({:CHANNEL, {:ok, chan}, _conn}, state) do
        new_state = State.connected(state, chan)
        handle_connect(new_state)
      end

      @doc false
      def handle_info({:CHANNEL, {:error, reason}, _conn}, state),
        do: {:disconnect, reason, state}
    end
  end
end
