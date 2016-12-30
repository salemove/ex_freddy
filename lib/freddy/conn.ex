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

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @otp_app Keyword.fetch!(opts, :otp_app)
      @supervisor String.to_atom("#{__MODULE__}.Supervisor")

      use Confex, otp_app: @otp_app
      use Supervisor

      def start_link,
        do: Supervisor.start_link(__MODULE__, [], name: @supervisor)

      def stop,
        do: Supervisor.stop(@supervisor)

      def status,
        do: Freddy.Conn.status(__MODULE__)

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
  def start_link(opts \\ []) do
    gen_server_opts = Keyword.take(opts, [:name])
    Connection.start_link(__MODULE__, opts, gen_server_opts)
  end

  @doc """
  Start Freddy connection process without linking it to the calling process.
  """
  def start(opts \\ []) do
    gen_server_opts = Keyword.take(opts, [:name])
    Connection.start(__MODULE__, opts, gen_server_opts)
  end

  @doc """
  Synchronously open channel on a given connection. If connection to AMQP broker is lost and
  server is in reconnecting phase, the call is going to block until connection is established
  or server gave up on reconnecting.
  """
  def open_channel(conn),
    do: Connection.call(conn, :open_channel, :infinity)

  @doc """
  Asynchronously open channel on a given connection. Once channel is opened or error has happened,
  the calling process will receive a message `{:CHANNEL, result, conn_pid}` where `result` can be
  `{:ok, %Freddy.Conn.Chan{}}` or `{:error, reason}` and `conn_pid` is Freddy.Conn process id.
  """
  def request_channel(conn),
    do: Connection.cast(conn, {:request_channel, self()})

  @doc """
  Setup monitor on AMQP connection. If AMQP connection goes down, monitor will notify monitoring process.
  """
  def monitor(conn) do
    %{pid: pid} = given_conn(conn)
    Process.monitor(pid)
  end

  @doc """
  Returns status of AMQP connection.
  """
  def status(conn),
    do: Connection.call(conn, :status)

  @doc """
  Close AMQP connection and stop Freddy.Conn process.
  """
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
