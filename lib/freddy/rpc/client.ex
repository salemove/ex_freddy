defmodule Freddy.RPC.Client do
  @moduledoc """
  This module implements RPC pattern as described [here](https://www.rabbitmq.com/tutorials/tutorial-six-elixir.html).

  # Examples

  Client can be used as a stand-alone, non-supervised process:

  ```elixir
  {:ok, conn} = Freddy.Conn.start_link()
  {:ok, client} = Freddy.RPC.Client.start_link(conn, "QueueName")

  response = Freddy.RPC.Client.call(client, %{json: :payload})
  {:ok, data} = response
  ```

  Or it can be put under supervision tree:

  ```elixir
  defmodule MyApp.Connection do
    use Freddy.Conn, otp_app: :my_app
  end

  defmodule MyApp.RemoteServiceClient do
    use Freddy.RPC.Client,
        connection: MyApp.Connection,
        queue: "QueueName"

    def tweet(message) do
      call(%{action: "tweet", message: message})
    end
  end

  defmodule MyApp.Freddy do
    use Supervisor

    def start_link,
      do: Supervisor.start_link(__MODULE__, :ok)

    def init(_) do
      children = [
        suprevisor(MyApp.RemoteServiceClient, [])
      ]

      supervise(children, strategy: :rest_for_one)
    end
  end
  ```
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @supervisor String.to_atom("#{__MODULE__}.Supervisor")
      @connection Keyword.fetch!(opts, :connection)
      @queue Keyword.fetch!(opts, :queue)

      use Supervisor
      alias Freddy.RPC.Client

      def start_link do
        {:ok, _} = ensure_connected()
        Supervisor.start_link(__MODULE__, [], name: @supervisor)
      end

      def call(payload, opts \\ []),
        do: Client.call(__MODULE__, payload, opts)

      def stop,
        do: Supervisor.stop(@supervisor)

      def init(_) do
        children = [
          worker(Client, [@connection, @queue, [name: __MODULE__]])
        ]

        supervise(children, strategy: :one_for_one)
      end

      defp ensure_connected do
        case @connection.start_link() do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
      end
    end
  end

  use Connection

  require Logger

  alias __MODULE__.State

  @default_timeout 3000

  def start_link(conn, queue, opts \\ []),
    do: Connection.start_link(__MODULE__, [conn, queue], opts)

  def start(conn, queue, opts \\ []),
    do: Connection.start(__MODULE__, [conn, queue], opts)

  def call(client, payload, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    opts = Keyword.merge(opts, timeout: timeout)

    try do
      Connection.call(client, {:call, payload, opts}, timeout)
    catch
      :exit, {reason, _} -> {:error, reason}
    end
  end

  def stop(client),
    do: Connection.call(client, {:close, :normal})

  @doc false
  def reply(client, correlation_id, response),
    do: Connection.cast(client, {:RPC_RESPONSE, correlation_id, response})

  # Connection/GenServer callbacks

  def init([conn, queue]) do
    Process.flag(:trap_exit, true)
    {:connect, :init, State.new(conn, queue)}
  end

  def connect(:reconnect, state),
    do: {:ok, State.reconnect(state)}

  def connect(_info, state),
    do: {:ok, State.connect(state)}

  def disconnect(reason, state),
    do: {:stop, reason, state}

  def terminate(_reason, state),
    do: State.disconnect(state)

  def handle_call({:call, payload, opts}, from, state),
    do: State.request(state, from, payload, opts)

  def handle_call({:close, reason}, _from, state),
    do: {:disconnect, reason, :ok, state}

  def handle_cast({:RPC_RESPONSE, correlation_id, response}, state) do
    case State.reply(state, correlation_id, response) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, _} ->
        Logger.warn("Message with correlation_id #{correlation_id} received, but there is no requester")
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, _, _, reason}, state) do
    if State.down?(state, ref) do
      {:disconnect, reason, state}
    else
      {:noreply, state}
    end
  end

  # Producer or consumer notify that they have connected
  def handle_info({:GENQUEUE_CONNECTION, {:ok, :connected}, from}, state = %{consumer: from}),
    do: {:noreply, State.consumer_connected(state)}

  def handle_info({:GENQUEUE_CONNECTION, {:ok, :connected}, from}, state = %{producer: from}),
    do: {:noreply, State.producer_connected(state)}

  def handle_info({:GENQUEUE_CONNECTION, {:ok, :connected}, _from}, state),
    do: {:noreply, state}

  def handle_info({:GENQUEUE_CONNECTION, _error, _from}, state) do
    {:connect, :reconnect, state}
  end

  def handle_info({:EXIT, _from, :normal}, state),
    do: {:noreply, state}

  # Reconnect if consumer is dead
  def handle_info({:EXIT, from, _reason}, state = %{consumer: from}),
    do: {:connect, :reconnect, state}

  # Reconnect if producer is dead
  def handle_info({:EXIT, from, _reason}, state = %{producer: from}),
    do: {:connect, :reconnect, state}

  # Ignore other EXIT messages, because they may come when Client is already restarted and recovered
  def handle_info({:EXIT, _from, _reason}, state),
    do: {:noreply, state}
end
