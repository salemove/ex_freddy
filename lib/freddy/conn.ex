defmodule Freddy.Conn do
  @moduledoc """
  AMQP Connection module.

  Can be used in another module to implement connecton supervisor:

  ```
  defmodule MyApp.MyConnection do
    use Freddy.Conn, otp_app: :my_app
  end

  MyApp.MyConnection.start_link()
  {:ok, chan} = MyApp.MyConnection.open_channel()
  ```

  You shouldn't directly use this module in your application code.
  """

  @typedoc """
  Freddy Connection reference.
  """
  @type connection :: GenServer.server

  @typedoc """
  Freddy.Conn name. See GenServer.name type.
  """
  @type name :: GenServer.name

  @typedoc """
  Options used by the `start*` functions.
  """
  @type options :: [option]

  @typedoc """
  Connection option values. See AMQP.Connection.open/1 for options description.
  """
  @type option :: {:name, name}
                | {:adapter, adapter}
                | {:host, binary}
                | {:port, integer}
                | {:username, binary}
                | {:password, binary}
                | {:virtual_host, binary}
                | {:channel_max, integer}
                | {:frame_max, integer}
                | {:heartbeat, integer}
                | {:connection_timeout, integer | :infinity}
                | {:client_properties, client_properties}
                | {:ssl_options, ssl_options}
                | {:history, history}

  @typedoc """
  AMQP Connection adapter. Use :sandbox for unit testing and :amqp for real world applications.
  """
  @type adapter :: :amqp | :sandbox

  @typedoc """
  A list of extra client properties to be sent to the server.
  """
  @type client_properties :: [client_option]

  @typedoc false
  @type client_option :: {term, term}

  @typedoc false
  @type ssl_options :: [ssl_option]

  @typedoc false
  @type ssl_option :: {:cacertfile, binary}
                    | {:certfile, binary}
                    | {:keyfile, binary}
                    | {:verify, atom}

  @typedoc """
  Reference to connection events history collector.

  Only for :sandbox adapter.
  """
  @type history :: GenServer.server
                 | true

  @typedoc """
  Return values of `start*` functions.
  """
  @type on_start :: GenServer.on_start

  @typedoc """
  Alias to Freddy.Conn.Channel type.
  """
  @type channel :: Freddy.Conn.Channel.t

  @typedoc """
  Freddy connection status.
  """
  @type status :: :connected
                | :not_connected
                | :reconnecting

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @moduledoc """
      Freddy connection supervisor. Put it under application supervision tree.
      """

      @otp_app Keyword.fetch!(opts, :otp_app)
      @supervisor String.to_atom("#{__MODULE__}.Supervisor")

      use Confex, otp_app: @otp_app
      use Supervisor

      @doc """
      Establishes AMQP connection (uses application config key #{inspect @otp_app}),
      registers it under name #{inspect __MODULE__} and starts supervising established connection.
      Started supervisor is registered under name #{inspect @supervisor}.

      Return values are the same as for `Supervisor.start_link/3`.
      """
      @spec start_link() :: Supervisor.on_start
      def start_link,
        do: Supervisor.start_link(__MODULE__, [], name: @supervisor)

      @doc """
      Closes #{inspect __MODULE__} AMQP connection with given `reason`.

      Return values are the same as for `Supervisor.stop/3`.
      """
      @spec stop(reason :: term) :: :ok
      def stop(reason \\ :normal),
        do: Supervisor.stop(@supervisor, reason)

      @doc """
      Returns #{inspect __MODULE__} AMQP connection status
      """
      @spec status() :: Freddy.Conn.status
      def status,
        do: Freddy.Conn.status(__MODULE__)

      @doc false
      def init(_) do
        children = [
          # Start Conn process and register it under name=$__MODULE__
          worker(Freddy.Conn, [config() ++ [name: __MODULE__]])
        ]

        supervise(children, strategy: :one_for_one)
      end
    end
  end

  use Connection

  require Logger

  alias Freddy.Conn.State

  # Public interface

  @doc """
  Start Freddy connection process and link it the calling process.
  """
  @spec start_link(options) :: on_start
  def start_link(options \\ []) do
    gen_server_opts = Keyword.take(options, [:name])
    Connection.start_link(__MODULE__, options, gen_server_opts)
  end

  @doc """
  Start Freddy connection process without linking it to the calling process.
  """
  @spec start(options) :: on_start
  def start(options \\ []) do
    gen_server_opts = Keyword.take(options, [:name])
    Connection.start(__MODULE__, options, gen_server_opts)
  end

  @doc """
  Synchronously open channel on a given connection. If connection to AMQP broker is lost and
  server is in reconnecting phase, the call is going to block until connection is established
  or server gave up on reconnecting.
  """
  @spec open_channel(connection) ::
    {:ok, channel} | {:error, term}
  def open_channel(conn),
    do: Connection.call(conn, :open_channel, :infinity)

  @doc """
  Asynchronously open channel on a given connection. Once channel is opened or error has happened,
  the calling process will receive a message `{:CHANNEL, result, conn_pid}` where `result` can be
  `{:ok, %Freddy.Conn.Chan{}}` or `{:error, reason}` and `conn_pid` is Freddy.Conn process id.
  """
  @spec request_channel(connection) :: :ok
  def request_channel(conn),
    do: Connection.cast(conn, {:request_channel, self()})

  @doc """
  Setup monitor on AMQP connection. If AMQP connection goes down, monitor will notify monitoring process.
  """
  @spec monitor(connection) :: reference
  def monitor(conn) do
    %{pid: pid} = given_conn(conn)
    Process.monitor(pid)
  end

  @doc """
  Returns status of AMQP connection.
  """
  @spec status(connection) :: status
  def status(conn),
    do: Connection.call(conn, :status)

  @doc """
  Close AMQP connection and stop Freddy.Conn process.
  """
  @spec stop(connection, reason :: term) :: :ok
  def stop(conn, reason \\ :normal),
    do: Connection.call(conn, {:close, reason})

  @doc false
  def given_conn(conn),
    do: Connection.call(conn, :given_conn)

  # Connection callbacks

  @doc false
  def init(opts) do
    state =
      opts
      |> Confex.process_env()
      |> State.new()

    {:connect, :init, state}
  end

  @doc false
  def connect(_info, state) do
    case State.connect(state) do
      {:ok, new_state} ->
        Logger.debug("RabbitMQ connection established #{inspect State.given_conn(new_state)}")
        {:ok, new_state}

      {:retry, reason, interval, new_state} ->
        Logger.warn("Couldn't connect to RabbitMQ, reason: #{inspect reason}. Retrying in #{interval} ms")
        {:backoff, interval, new_state}

      {:exhausted, reason, new_state} ->
        Logger.error("Couldn't establish connection to RabbitMQ, reason: #{inspect reason}")
        {:stop, :no_connection, new_state}
    end
  end

  @doc false
  def disconnect(reason, state),
    do: {:stop, reason, state}

  # GenServer callbacks

  @doc false
  def handle_call(:open_channel, from, state) do
    case State.open_channel(state, from) do
      {:wait, new_state} -> {:noreply, new_state}
      result             -> {:reply, result, state}
    end
  end

  def handle_call(:given_conn, _from, state),
    do: {:reply, State.given_conn(state), state}

  def handle_call(:status, _from, state),
    do: {:reply, State.status(state), state}

  def handle_call({:close, reason}, _from, state),
    do: {:disconnect, reason, :ok, state}

  @doc false
  def handle_cast({:request_channel, from}, state),
    do: {:noreply, State.request_channel(state, from)}

  @doc false
  def handle_info({:DOWN, ref, _, _, reason}, state) do
    if State.down?(state, ref) do
      Logger.warn("RabbitMQ connection went down: #{inspect reason}")
      {:connect, :reconnect, state}
    else
      {:noreply, state}
    end
  end

  @doc false
  def terminate(_reason, state),
    do: State.disconnect(state)
end
