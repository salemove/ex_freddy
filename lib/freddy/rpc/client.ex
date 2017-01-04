defmodule Freddy.RPC.Client do
  @moduledoc """
  This module implements RPC pattern as described [here](https://www.rabbitmq.com/tutorials/tutorial-six-elixir.html).

  # Examples

  Client can be used as a standalone, non-supervised process:

  ```elixir
  {:ok, conn} = Freddy.Conn.start_link()
  {:ok, client} = Freddy.RPC.Client.start_link(conn, "QueueName")

  response = Freddy.RPC.Client.call(client, "payload")
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

    # Include middleware to encode message to JSON and parse JSON response
    plug Middleware.JSON, engine: Poison

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

  @typedoc "Freddy connection or RPC client reference."
  @type server :: GenServer.server

  @typedoc "Return values of `start*` functions."
  @type on_start :: GenServer.on_start

  @typedoc "Allowed values for 3rd argument of `start*` functions."
  @type start_options :: GenServer.options

  @typedoc "Allowed values for 3rd argument of `call` function."
  @type req_options :: [req_option]
  @type req_option :: {:immediate, boolean}
                    | {:content_encoding, String.t}
                    | {:headers, Keyword.t}
                    | {:persistent, boolean}
                    | {:priority, 0..9}
                    | {:timeout, timeout}
                    | {:message_id, String.t}
                    | {:timestamp, any}
                    | {:user_id, integer}
                    | {:app_id, String.t}


  @doc """
  When used, defines the current module as AMQP RPC Client.

  There are 2 ways to create client - by using existing Freddy connection supervisor
  and by creating (and supervising) separate connection.

  # Example 1. Using existing connection.

  This scenario is useful when you want to create few RPC Clients which will use
  same AMQP connection.

    defmodule MyConnection do
      use Freddy.Conn, otp_app: :my_app
    end

    defmodule PushNotificationsClient do
      use Freddy.RPC.Client,
          connection: MyConnection,
          queue: "push_notifications"
    end

    defmodule MailNotificationsClient do
      use Freddy.RPC.Client,
          connection: MyConnection
          queue: "smtp_queue"
    end

    # Now to be safe you should put them altogether under the same supervision tree
    # and start this supverision tree on your application starts.

    defmodule AMQPServicesSupervisor do
      use Supervisor

      def init(_) do
        children = [
          supervisor(MyConnection, []),
          supervisor(PushNotificationsClient, []),
          supervisor(MailNotificationsClient, [])
        ]

        supervise(children, strategy: :rest_for_one)
      end
    end

  # Example 2. Creating new connection.

    defmodule MyClient do
      use Freddy.RPC.Client,
          otp_app: :my_app,
          queue: "my_client_queue"
    end

    MyClient.start_link()
    MyClient.call(some_payload)

    # Put client under application supervision tree.

  # Options

    * `:connection` - Freddy.Connection supervisor process name. In the given example you should use `MyConnection` atom:

        defmodule MyConnection do
          use Freddy.Conn, otp_app: :my_app
        end

        defmodule MyClient do
          use Freddy.RPC.Client, connection: MyConnection
        end

    * `:otp_app` - This option should point to an OTP application that has connection configuration.

    * `:queue` - Name of the queue where AMQP messages will be delivered. There shoould be a process,
      which will consume messages from this queue and respond back, otherwise RPC requests will end
      with either `{:error, :no_route}` or `{:error, :timeout}`

  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias Freddy.RPC.Client
      alias Client.Middleware

      use Supervisor
      use Client.Builder

      # Process names
      @supervisor String.to_atom("#{__MODULE__}.Supervisor")
      @client __MODULE__
      @connection Keyword.get(opts, :connection, String.to_atom("#{__MODULE__}.Connection"))
      @spawn_connection? Keyword.has_key?(opts, :otp_app)

      @queue Keyword.fetch!(opts, :queue)

      def start_link do
        Supervisor.start_link(__MODULE__, [], name: @supervisor)
      end

      def call(payload, opts \\ []) do
        opts = Keyword.put(opts, :__middleware__, __middleware__())
        Client.call(@client, payload, opts)
      end

      def stop,
        do: Supervisor.stop(@supervisor)

      def init(_) do
        supervise(children_spec(), strategy: :rest_for_one)
      end

      if @spawn_connection? do
        use Confex, otp_app: Keyword.fetch!(opts, :otp_app)

        defp children_spec do
          [
            worker(Freddy.Conn, [config() ++ [name: @connection]]),
            worker(Client, [@connection, @queue, [name: @client]])
          ]
        end
      else
        defp children_spec do
          [worker(Client, [@connection, @queue, [name: @client]])]
        end
      end
    end
  end

  alias Freddy.RPC.Client.{Builder,
                           State,
                           Request,
                           Middleware}

  use Connection
  use Builder
  require Logger

  # Default Middleware stack
  plug Middleware.Timeout, default: 3000
  plug Middleware.RPCRequest

  @doc """
  Start RPC Client and link to the calling process.

  See `GenServer.start_link/3` for available options.
  """
  @spec start_link(server, queue :: String.t, opts :: start_options) :: on_start
  def start_link(conn, queue, opts \\ []),
    do: Connection.start_link(__MODULE__, [conn, queue], opts)

  @doc """
  Start RPC Client witout linking it to the calling process.

  See `GenServer.start/3` for available options.
  """
  @spec start(server, queue :: String.t, opts :: start_options) :: on_start
  def start(conn, queue, opts \\ []),
    do: Connection.start(__MODULE__, [conn, queue], opts)

  @doc """
  Synchronously perform RPC request over AMQP.

  This method will return either `{:ok, result}` or `{:error, reason}`.
  Request timeout can be specified with `:timeout` option.
  """
  @spec call(server, payload :: any, req_options) ::
    {:ok, result :: any} |
    {:error, reason :: term}
  def call(client, payload, opts \\ []) do
    client
    |> Request.new(payload, opts)
    |> Middleware.run(build_middleware_stack(opts))
  end

  @doc """
  Gracefully stop RPC Client.
  """
  @spec stop(server) :: :ok
  def stop(client),
    do: Connection.call(client, {:close, :normal})

  # Private API

  @doc false
  def reply_queue(client),
    do: Connection.call(client, :reply_queue)

  @doc false
  def destination_queue(client),
    do: Connection.call(client, :destination_queue)

  @doc false
  def perform_request(request = %Request{client: client, payload: payload, opts: opts, env: env}) do
    result =
      if Map.has_key?(env, :client_timeout) do
        Connection.call(client, {:call, payload, opts}, env[:client_timeout])
      else
        Connection.call(client, {:call, payload, opts})
      end

    case result do
      {:ok, payload, opts} ->
        %{request | payload: payload, opts: opts, status: :ok}

      {:error, reason} ->
        %{request | status: :error, error: reason}
    end
  end

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

  def handle_call(:reply_queue, _from, state) do
    {:reply, state.reply_queue, state}
  end

  def handle_call(:destination_queue, _from, state) do
    {:reply, state.queue, state}
  end

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

  # Private functions

  @core_middleware [
    {Middleware.ErrorHandler, :call, []},
    {__MODULE__, :perform_request}
  ]

  defp build_middleware_stack(opts) do
    __middleware__() ++
    Keyword.get(opts, :__middleware__, []) ++
    @core_middleware
  end
end
