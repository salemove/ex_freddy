defmodule Freddy.RPC.Server do
  @moduledoc """
  A behaviour module for implementing AMQP RPC server processes.

  The `Freddy.RPC.Server` module provides a way to create processes that hold,
  monitor, and restart a channel in case of failure, and have some callbacks
  to hook into the process lifecycle and handle messages.

  An example `Freddy.RPC.Server` process that responds messages with `"ping"` as
  payload with a `"pong"` response, otherwise it does not reply but calls a given
  handler function with the payload and a callback function asynchronously, so
  the handler can respond when the message is processed:

      defmodule MyRPC.Server do
        use Freddy.RPC.Server

        def start_link(conn, config, handler) do
          Freddy.RPC.Server.start_link(__MODULE__, conn, config, handler)
        end

        def init(handler) do
          {:ok, %{handler: handler}}
        end

        def handle_request("ping", _meta, state) do
          {:reply, "pong", state}
        end

        def handle_request(payload, meta, %{handler: handler} = state) do
          callback = &Freddy.RPC.Server.reply(self(), meta, &1)
          Task.start_link(fn -> handler.(payload, callback) end)

          {:noreply, state}
        end
      end

  ## Channel handling

  When the `Freddy.RPC.Server` starts with `start_link/5` it runs the `init/1` callback
  and responds with `{:ok, pid}` on success, like a `GenServer`.

  After starting the process it attempts to open a channel on the given connection.
  It monitors the channel, and in case of failure it tries to reopen again and again
  on the same connection.

  ## Context setup

  The context setup process for a RPC server is to declare an exchange, then declare
  a queue to consume, and then bind the queue to the exchange. It also creates a
  default exchange to use it to respond to the reply-to queue.

  Every time a channel is open the context is set up, meaning that the queue and
  the exchange are declared and binded through the new channel based on the given
  configuration.

  The configuration must be a `Keyword.t` that contains the same keys as `Freddy.Consumer`.
  Check out `Freddy.Consumer` documentation for the list of available configuration keys.

  ## Ack mode

  By default RPC server starts in automatic acknowledgement mode. It means that all
  incoming requests will be acknowledged automatically by RabbitMQ server once delivered
  to a client (RPC server process).

  If your logic requires manual acknowledgements, you should start server with configuration
  option `[consumer: [no_ack: false]]` and acknowledge messages manually using `ack/2` function.

  Below is an example of how to start a server in manual acknowledgement mode:

      defmodule MyRPC.Server do
        alias Freddy.RPC.Server
        use Server

        def start_link(conn, handler) do
          config = [
            queue: [name: "rpc-queue"],
            consumer: [no_ack: false]
          ]

          Server.start_link(__MODULE__, conn, config, handler)
        end

        def handle_request(payload, meta, handler) do
          result = handler.handle_request(payload)
          Server.ack(meta)
          {:reply, result, handler}
        end
      end
  """

  @type payload :: String.t()
  @type request :: term
  @type response :: term
  @type routing_key :: String.t()
  @type opts :: Keyword.t()
  @type meta :: map
  @type state :: term

  @doc """
  Called when the RPC server process is first started. `start_link/5` will block
  until it returns.

  It receives as argument the fourth argument given to `start_link/5`.

  Returning `{:ok, state}` will cause `start_link/5` to return `{:ok, pid}`
  and attempt to open a channel on the given connection, declare the exchange,
  declare a queue, and start consumption. After that it will enter the main loop
  with `state` as its internal state.

  Returning `:ignore` will cause `start_link/5` to return `:ignore` and the
  process will exit normally without entering the loop, opening a channel or calling
  `c:terminate/2`.

  Returning `{:stop, reason}` will cause `start_link/5` to return `{:error, reason}` and
  the process will exit with reason `reason` without entering the loop, opening a channel,
  or calling `c:terminate/2`.
  """
  @callback init(initial :: term) ::
              {:ok, state}
              | :ignore
              | {:stop, reason :: term}

  @doc """
  Called when the RPC server process has opened AMQP channel before registering
  itself as a consumer.

  First argument is a map, containing `:channel`, `:exchange` and `:queue` structures.

  Returning `{:noreply, state}` will cause the process to enter the main loop
  with the given state.

  Returning `{:error, state}` will cause the process to reconnect (i.e. open
  new channel, declare exchange and queue, etc).

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback handle_connected(Freddy.Consumer.connection_info(), state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:error, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when the AMQP server has registered the process as a consumer of the
  server-named queue and it will start to receive messages.

  Returning `{:noreply, state}` will causes the process to enter the main loop
  with the given state.

  Returning `{:stop, reason, state}` will not send the message, terminate
  the main loop and call `c:terminate/2` before the process exits with
  reason `reason`.
  """
  @callback handle_ready(meta, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  @doc """
  Called when the RPC server has been disconnected from the AMQP broker.

  Returning `{:noreply, state}` will cause the process to enter the main loop
  with the given state. The server will not consume any new messages until
  connection to AMQP broker is restored.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback handle_disconnected(reason :: term, state) ::
              {:noreply, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when a request message is delivered from the queue before passing it into a
  `handle_request` function.

  The arguments are the message's payload, some metadata and the internal state.

  The metadata is a map containing all metadata given by the AMQP client when receiving
  the message plus the `:exchange` and `:queue` values.

  Returning `{:ok, request, state}` will pass the returned request term into
  `c:handle_message/3` function.

  Returning `{:ok, request, meta, state}` will pass the returned request term
  and the meta into `c:handle_message/3` function.

  Returning `{:reply, response, state}` will publish response message without calling
  `c:handle_message/3` function. Function `c:encode_response/3` will be called before
  publishing the response.

  Returning `{:reply, response, opts, state}` will publish the response message
  with returned options without calling `c:handle_message/3` function. Function
  `c:encode_response/3` will be called before publishing the response.

  Returning `{:noreply, state}` will ignore that message and enter the main loop
  again with the given state.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback decode_request(payload, meta, state) ::
              {:ok, request, state}
              | {:reply, response, state}
              | {:reply, response, opts, state}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  @doc """
  Called when a request message has been successfully decoded by `c:decode_request/3`
  function.

  The arguments are the message's decoded payload, some metadata and the internal state.

  The metadata is a map containing all metadata given by the AMQP client when receiving
  the message plus the `:exchange` and `:queue` values.

  Returning `{:reply, response, state}` will publish response message. Function
  `c:encode_response/3` will be called before  publishing the response.

  Returning `{:reply, response, opts, state}` will publish the response message
  with returned options. Function `c:encode_response/3` will be called before publishing
  the response.

  Returning `{:noreply, state}` will ignore that message and enter the main loop
  again with the given state.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback handle_request(request, meta, state) ::
              {:reply, response, state}
              | {:reply, response, opts, state}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  @doc """
  Called before a response message will be published to the default exchange.

  It receives as argument the message payload, the options for that
  publication and the internal state.

  Returning `{:reply, string, state}` will cause the returned `string` to be
  published to the exchange, and the process to enter the main loop with the
  given state.

  Returning `{:reply, string, opts, state}` will cause the returned `string` to be
  published to the exchange with the returned options, and enter the main loop with
  the given state.

  Returning `{:noreply, state}` will ignore that message and enter the main loop
  again with the given state.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback encode_response(response, opts, state) ::
              {:reply, payload, state}
              | {:reply, payload, opts, state}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  @doc """
  Called when the process receives a call message sent by `call/3`. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:reply`, `:noreply` and `:stop` return tuples behave the same.
  """
  @callback handle_call(request, GenServer.from(), state) ::
              {:reply, reply :: term, state}
              | {:reply, reply :: term, state, timeout | :hibernate}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}
              | {:stop, reason :: term, reply :: term, state}

  @doc """
  Called when the process receives a cast message sent by `cast/2`. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:noreply` and `:stop` return tuples behave the same.
  """
  @callback handle_cast(request, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  @doc """
  Called when the process receives a message. This callback has the same
  arguments as the `GenServer` equivalent and the `:noreply` and `:stop`
  return tuples behave the same.
  """
  @callback handle_info(message :: term, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  @doc """
  This callback is the same as the `GenServer` equivalent and is called when the
  process terminates. The first argument is the reason the process is about
  to exit with.
  """
  @callback terminate(reason :: term, state) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @impl true
      def init(initial) do
        {:ok, initial}
      end

      @impl true
      def handle_connected(_meta, state) do
        {:noreply, state}
      end

      @impl true
      def handle_ready(_meta, state) do
        {:noreply, state}
      end

      @impl true
      def handle_disconnected(_meta, state) do
        {:noreply, state}
      end

      @impl true
      def decode_request(payload, _meta, state) do
        case Jason.decode(payload) do
          {:ok, decoded} -> {:ok, decoded, state}
          {:error, reason} -> {:stop, {:bad_request, payload}, state}
        end
      end

      @impl true
      # Part of Freddy custom RPC protocol
      # TODO: remove it from the library to a custom integration app
      def encode_response({:ok, payload}, opts, state) do
        encode_response(
          %{success: true, output: payload},
          Keyword.put(opts, :type, "response"),
          state
        )
      end

      def encode_response({:error, reason}, opts, state) do
        encode_response(%{success: false, error: reason}, Keyword.put(opts, :type, "error"), state)
      end

      def encode_response(response, opts, state) do
        case Jason.encode(response) do
          {:ok, payload} ->
            opts = Keyword.put(opts, :content_type, "application/json")
            {:reply, payload, opts, state}

          {:error, reason} ->
            {:stop, {:bad_response, response}, state}
        end
      end

      @impl true
      def handle_call(message, _from, state) do
        {:stop, {:bad_call, message}, state}
      end

      @impl true
      def handle_cast(message, state) do
        {:stop, {:bad_cast, message}, state}
      end

      @impl true
      def handle_info(_message, state) do
        {:noreply, state}
      end

      @impl true
      def terminate(_reason, _state) do
        :ok
      end

      defoverridable unquote(__MODULE__)
    end
  end

  use Freddy.Consumer

  alias Freddy.Core.Exchange

  @doc """
  Start a `Freddy.RPC.Server` process linked to the current process.

  Arguments:

    * `mod` - the module that defines the server callbacks (like `GenServer`)
    * `connection` - the pid of a `Freddy.Connection` process
    * `config` - the configuration of the RPC server
    * `initial` - the value that will be given to `c:init/1`
    * `opts` - the GenServer options
  """
  @spec start_link(
          module,
          Freddy.Consumer.connection(),
          Keyword.t(),
          initial :: term,
          GenServer.options()
        ) :: GenServer.on_start()
  def start_link(mod, connection, config, initial, opts \\ []) do
    Freddy.Consumer.start_link(__MODULE__, connection, prepare_config(config), {mod, initial}, opts)
  end

  @doc """
  Start a `Freddy.RPC.Server` process without linking to the current process.

  See `start_link/5` for more information.
  """
  @spec start(
          module,
          Freddy.Consumer.connection(),
          Keyword.t(),
          initial :: term,
          GenServer.options()
        ) :: GenServer.on_start()
  def start(mod, connection, config, initial, opts \\ []) do
    Freddy.Consumer.start(__MODULE__, connection, prepare_config(config), {mod, initial}, opts)
  end

  @doc """
  Responds a request given its meta
  """
  @spec reply(GenServer.server(), meta, response, Keyword.t()) :: :ok
  def reply(server, request_meta, response, opts \\ []) do
    Freddy.Consumer.cast(server, {:"$reply", request_meta, response, opts})
  end

  defdelegate ack(meta, opts \\ []), to: Freddy.Consumer
  defdelegate call(client, message, timeout \\ 5000), to: Freddy.Consumer
  defdelegate cast(client, message), to: Freddy.Consumer
  defdelegate stop(client, reason \\ :normal), to: GenServer

  defp prepare_config(config) do
    Keyword.update(config, :consumer, [no_ack: true], &Keyword.put_new(&1, :no_ack, true))
  end

  import Record
  defrecordp :state, mod: nil, given: nil

  @impl true
  def init({mod, initial}) do
    case mod.init(initial) do
      {:ok, given} ->
        {:ok, state(mod: mod, given: given)}

      :ignore ->
        :ignore

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_connected(meta, state(mod: mod, given: given) = state) do
    case mod.handle_connected(meta, given) do
      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:error, new_given} ->
        {:error, state(state, given: new_given)}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  @impl true
  def handle_ready(meta, state(mod: mod, given: given) = state) do
    case mod.handle_ready(meta, given) do
      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  @impl true
  def handle_disconnected(reason, state(mod: mod, given: given) = state) do
    case mod.handle_disconnected(reason, given) do
      {:noreply, new_given} -> {:noreply, state(state, given: new_given)}
      {:stop, reason, new_given} -> {:stop, reason, state(state, given: new_given)}
    end
  end

  @impl true
  def decode_message(payload, meta, given) do
    {:ok, payload, meta, given}
  end

  @impl true
  def handle_message(payload, meta, state(mod: mod, given: given) = state) do
    case mod.decode_request(payload, meta, given) do
      {:ok, new_payload, new_given} ->
        new_payload
        |> mod.handle_request(meta, new_given)
        |> handle_mod_response(meta, state)

      other ->
        handle_mod_response(other, meta, state)
    end
  end

  @impl true
  def handle_call(request, from, state(mod: mod, given: given) = state) do
    case mod.handle_call(request, from, given) do
      {:reply, response, new_given} ->
        {:reply, response, state(state, given: new_given)}

      {:reply, response, new_given, timeout} ->
        {:reply, response, state(state, given: new_given), timeout}

      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, response, new_given} ->
        {:stop, reason, response, state(state, given: new_given)}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  @impl true
  def handle_cast({:"$reply", meta, response, opts}, state) do
    send_response(response, opts, meta, state)
  end

  def handle_cast(message, state(mod: mod, given: given) = state) do
    message
    |> mod.handle_cast(given)
    |> handle_async_response(state)
  end

  @impl true
  def handle_info(message, state(mod: mod, given: given) = state) do
    message
    |> mod.handle_info(given)
    |> handle_async_response(state)
  end

  @impl true
  def terminate(reason, state(mod: mod, given: given)) do
    mod.terminate(reason, given)
  end

  defp handle_mod_response(response, meta, state) do
    case response do
      {:reply, response, new_given} ->
        send_response(response, [], meta, state(state, given: new_given))

      {:reply, response, opts, new_given} ->
        send_response(response, opts, meta, state(state, given: new_given))

      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  defp send_response(response, opts, req_meta, state(mod: mod, given: given) = state) do
    case mod.encode_response(response, opts, given) do
      {:reply, payload, new_given} ->
        publish_response(req_meta, payload, opts)
        {:noreply, state(state, given: new_given)}

      {:reply, payload, opts, new_given} ->
        publish_response(req_meta, payload, opts)
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  defp publish_response(
         %{correlation_id: correlation_id, reply_to: target, channel: channel} = _meta,
         payload,
         opts
       ) do
    opts = Keyword.put(opts, :correlation_id, correlation_id)
    Exchange.publish(Exchange.default(), channel, payload, target, opts)
  end

  defp handle_async_response(response, state) do
    case response do
      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end
end
