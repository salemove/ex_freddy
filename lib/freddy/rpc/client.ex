defmodule Freddy.RPC.Client do
  @moduledoc ~S"""
  This module allows to build RPC client for any Freddy-compliant microservice.

  ## Example

      defmodule PaymentsService do
        use Freddy.RPC.Client

        @config [timeout: 3500]

        def start_link(conn, initial, opts \\ []) do
          Freddy.RPC.Client.start_link(__MODULE__, conn, @config, initial, opts)
        end
      end

      {:ok, client} = PaymentsService.start_link()
      PaymentsService.request(client, "Payments", %{type: "get_history", site_id: "xxx"})
  """

  @type payload :: term
  @type request :: Freddy.RPC.Request.t()
  @type response :: term
  @type routing_key :: String.t()
  @type opts :: Keyword.t()
  @type meta :: map
  @type state :: term

  @doc """
  Called when the RPC client process is first started. `start_link/5` will block
  until it returns.

  It receives as argument the fourth argument given to `start_link/5`.

  Returning `{:ok, state}` will cause `start_link/5` to return `{:ok, pid}`
  and attempt to open a channel on the given connection, declare the exchange,
  declare a server-named queue, and consume it.
  After that it will enter the main loop with `state` as its internal state.

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
  Called when the RPC client process has opened AMQP channel before registering
  itself as a consumer.

  Returning `{:noreply, state}` will cause the process to enter the main loop
  with the given state.

  Returning `{:error, state}` will cause the process to reconnect (i.e. open
  new channel, declare exchange and queue, etc).

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback handle_connected(state) ::
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
  Called when the AMQP server has been disconnected from the AMQP broker.

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
  Called before a request will be performed to the exchange.

  It receives as argument the RPC request structure which contains the message
  payload, the routing key and the options for that publication, and the
  internal client state.

  Returning `{:ok, state}` will cause the request to be performed with no
  modification, block the client until the response is received, and enter
  the main loop with the given state.

  Returning `{:ok, request, state}` will cause the payload, routing key and
  options from the given `request` to be used instead of the original ones,
  block the client until the response is received, and enter the main loop
  with the given state.

  Returning `{:reply, response, state}` will respond the client inmediately
  without performing the request with the given response, and enter the main
  loop again with the given state.

  Returning `{:stop, reason, response, state}` will not send the message,
  respond to the caller with `response`, terminate the main loop
  and call `c:terminate/2` before the process exits with reason `reason`.

  Returning `{:stop, reason, state}` will not send the message, terminate
  the main loop and call `c:terminate/2` before the process exits with
  reason `reason`.
  """
  @callback before_request(request, state) ::
              {:ok, state}
              | {:ok, request, state}
              | {:reply, response, state}
              | {:stop, reason :: term, response, state}
              | {:stop, reason :: term, state}

  @doc """
  Called before a message will be published to the exchange.

  It receives as argument the RPC request structure and the internal state.

  Returning `{:ok, request, state}` will cause the returned `request` to be
  published to the exchange, and the process to enter the main loop with the
  given state.

  Returning `{:reply, response, state}` will respond the client inmediately
  without performing the request with the given response, and enter the main
  loop again with the given state.

  Returning `{:stop, reason, response, state}` will not send the message,
  respond to the caller with `response`, and terminate the main loop
  and call `c:terminate/2` before the process exits with reason `reason`.

  Returning `{:stop, reason, state}` will not send the message, terminate
  the main loop and call `c:terminate/2` before the process exits with
  reason `reason`.
  """
  @callback encode_request(request, state) ::
              {:ok, request, state}
              | {:reply, response, state}
              | {:reply, response, state, timeout | :hibernate}
              | {:stop, reason :: term, response, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when a response message is delivered from the queue before passing it into a
  `on_response` function.

  The arguments are the message's raw payload, response metatdata, original RPC request
  for which the response has arrived, and the internal state.

  The metadata is a map containing all metadata given by the AMQP client when receiving
  the message plus the `:exchange` and `:queue` values.

  Returning `{:ok, payload, state}` or `{:ok, payload, meta, state}` will pass the decoded
  payload and meta into `handle_message/3` function.

  Returning `{:noreply, state}` will do nothing, and therefore the message should
  be acknowledged by using `Freddy.Consumer.ack/2`, `Freddy.Consumer.nack/2` or
  `Freddy.Consumer.reject/2`.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback decode_response(payload :: String.t(), meta, request, state) ::
              {:ok, payload, state}
              | {:ok, payload, meta, state}
              | {:reply, reply :: term, state}
              | {:reply, reply :: term, state, timeout | :hibernate}
              | {:noreply, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when a response has been received, before it is delivered to the caller.

  It receives as argument the decoded and parse response, original RPC request
  for which the response has arrived, and the internal state.

  Returning `{:reply, reply, state}` will cause the given reply to be
  delivered to the caller instead of the original response, and enter
  the main loop with the given state.

  Returning `{:noreply, state}` will enter the main loop with the given state
  without responding to the caller (that will eventually timeout or keep blocked
  forever if the timeout was set to `:infinity`).

  Returning `{:stop, reason, reply, state}` will deliver the given reply to
  the caller instead of the original response and call `c:terminate/2`
  before the process exits with reason `reason`.

  Returning `{:stop, reason, state}` not reply to the caller and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback on_response(response, request, state) ::
              {:reply, response, state}
              | {:reply, response, state, timeout | :hibernate}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, response, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when a request has timed out.

  Returning `{:reply, reply, state}` will cause the given reply to be
  delivered to the caller, and enter the main loop with the given state.

  Returning `{:noreply, state}` will enter the main loop with the given state
  without responding to the caller (that will eventually timeout or keep blocked
  forever if the timeout was set to `:infinity`).

  Returning `{:stop, reason, reply, state}` will deliver the given reply to
  the caller, and call `c:terminate/2` before the process exits
  with reason `reason`.

  Returning `{:stop, reason, state}` will not reply to the caller and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback on_timeout(request, state) ::
              {:reply, response, state}
              | {:reply, response, state, timeout | :hibernate}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, response, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when a request has been returned by AMPQ broker.

  Returning `{:reply, reply, state}` will cause the given reply to be
  delivered to the caller, and enter the main loop with the given state.

  Returning `{:noreply, state}` will enter the main loop with the given state
  without responding to the caller (that will eventually timeout or keep blocked
  forever if the timeout was set to `:infinity`).

  Returning `{:stop, reason, reply, state}` will deliver the given reply to
  the caller, and call `c:terminate/2` before the process exits
  with reason `reason`.

  Returning `{:stop, reason, state}` will not reply to the caller and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback on_return(request, state) ::
              {:reply, response, state}
              | {:reply, response, state, timeout | :hibernate}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, response, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when the process receives a call message sent by `call/3`. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:reply`, `:noreply` and `:stop` return tuples behave the same.
  """
  @callback handle_call(request :: term, GenServer.from(), state) ::
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
  @callback handle_cast(request :: term, state) ::
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

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      @behaviour Freddy.RPC.Client

      @impl true
      def init(initial) do
        {:ok, initial}
      end

      @impl true
      def handle_connected(state) do
        {:noreply, state}
      end

      @impl true
      def handle_ready(_meta, state) do
        {:noreply, state}
      end

      @impl true
      def handle_disconnected(_reason, state) do
        {:noreply, state}
      end

      @impl true
      def before_request(_request, state) do
        {:ok, state}
      end

      @impl true
      def encode_request(request, state) do
        case Jason.encode(request.payload) do
          {:ok, new_payload} ->
            new_request =
              request
              |> Freddy.RPC.Request.set_payload(new_payload)
              |> Freddy.RPC.Request.put_option(:content_type, "application/json")

            {:ok, new_request, state}

          {:error, reason} ->
            {:reply, {:error, {:bad_request, reason}}, state}
        end
      end

      @impl true
      def decode_response(payload, _meta, _request, state) do
        case Jason.decode(payload) do
          {:ok, decoded} -> {:ok, decoded, state}
          {:error, reason} -> {:reply, {:error, {:bad_response, reason}}, state}
        end
      end

      @impl true
      def on_response(response, _request, state) do
        {:reply, response, state}
      end

      @impl true
      def on_timeout(_request, state) do
        {:reply, {:error, :timeout}, state}
      end

      @impl true
      def on_return(_request, state) do
        {:reply, {:error, :no_route}, state}
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

      defoverridable Freddy.RPC.Client
    end
  end

  use Freddy.Consumer

  require Record

  alias Freddy.RPC.Request
  alias Freddy.Exchange

  @type config :: [timeout: timeout, exchange: Keyword.t()]

  @default_timeout 3000
  @gen_server_timeout 5000

  @config [
    queue: [opts: [auto_delete: true, exclusive: true]],
    consumer: [no_ack: true]
  ]

  Record.defrecordp(
    :state,
    mod: nil,
    given: nil,
    timeout: @default_timeout,
    channel: nil,
    exchange: nil,
    queue: nil,
    waiting: %{}
  )

  @doc """
  Starts a `Freddy.RPC.Client` process linked to the current process.

  This function is used to start a `Freddy.RPC.Client` process in a supervision
  tree. The process will be started by calling `c:init/1` with the given initial
  value.

  Arguments:

    * `mod` - the module that defines the server callbacks (like `GenServer`)
    * `conn` - the pid of a `Freddy.Connection` process
    * `config` - the configuration of the RPC Client (describing the exchange and timeout value)
    * `initial` - the value that will be given to `c:init/1`
    * `opts` - the `GenServer` options
  """
  @spec start_link(module, GenServer.server(), config, initial :: term, GenServer.options()) ::
          GenServer.on_start()
  def start_link(mod, conn, config, initial, opts \\ []) do
    Freddy.Consumer.start_link(
      __MODULE__,
      conn,
      prepare_config(config),
      prepare_init_args(mod, config, initial),
      opts
    )
  end

  @doc """
  Starts a `Freddy.RPC.Client` process without linking to the current process,
  see `start_link/5` for more information.
  """
  @spec start(module, GenServer.server(), config, initial :: term, GenServer.options()) ::
          GenServer.on_start()
  def start(mod, conn, config, initial, opts \\ []) do
    Freddy.Consumer.start(
      __MODULE__,
      conn,
      prepare_config(config),
      prepare_init_args(mod, config, initial),
      opts
    )
  end

  defdelegate call(client, message, timeout \\ 5000), to: Connection
  defdelegate cast(client, message), to: Connection
  defdelegate stop(client, reason \\ :normal), to: GenServer

  @doc """
  Performs a RPC request and blocks until the response arrives.
  """
  @spec request(GenServer.server(), routing_key, payload, GenServer.options()) ::
          {:ok, response}
          | {:error, reason :: term}
          | {:error, reason :: term, hint :: term}
  def request(client, routing_key, payload, opts \\ []) do
    Freddy.Consumer.call(client, {:"$request", payload, routing_key, opts}, @gen_server_timeout)
  end

  defp prepare_config(config) do
    exchange = Keyword.get(config, :exchange, [])
    Keyword.put(@config, :exchange, exchange)
  end

  defp prepare_init_args(mod, config, initial) do
    timeout = Keyword.get(config, :timeout, @default_timeout)
    {mod, timeout, initial}
  end

  @impl true
  def init({mod, timeout, initial}) do
    case mod.init(initial) do
      {:ok, given} ->
        {:ok, state(mod: mod, given: given, timeout: timeout)}

      :ignore ->
        :ignore

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_connected(state(mod: mod, given: given) = state) do
    case mod.handle_connected(given) do
      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:error, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  @impl true
  def handle_ready(
        %{channel: channel, queue: queue, exchange: exchange} = meta,
        state(mod: mod, given: given) = state
      ) do
    :ok = AMQP.Basic.return(channel, self())
    new_state = state(state, channel: channel, exchange: exchange, queue: queue)

    case mod.handle_ready(meta, given) do
      {:noreply, new_given} ->
        {:noreply, state(new_state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(new_state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  @impl true
  def handle_disconnected(reason, state(mod: mod, given: given) = state) do
    disconnected = state(state, channel: nil, exchange: nil, queue: nil)

    case mod.handle_disconnected(reason, given) do
      {:noreply, new_given} -> {:noreply, state(disconnected, given: new_given)}
      {:stop, reason, new_given} -> {:stop, reason, state(disconnected, given: new_given)}
    end
  end

  @impl true
  def handle_call({:"$request", payload, routing_key, opts}, from, state) do
    handle_request(payload, routing_key, opts, from, state)
  end

  def handle_call(message, from, state(mod: mod, given: given) = state) do
    message
    |> mod.handle_call(from, given)
    |> handle_mod_callback(state)
  end

  @impl true
  def decode_message(
        payload,
        %{correlation_id: request_id} = meta,
        state(mod: mod, given: given) = state
      ) do
    pop_waiting(request_id, state, fn request, state ->
      case mod.decode_response(payload, meta, request, given) do
        {:ok, new_payload, new_given} ->
          {:ok, response_to_tuple(new_payload), Map.put(meta, :request, request),
           state(state, given: new_given)}

        {:ok, new_payload, new_meta, new_given} ->
          {:ok, response_to_tuple(new_payload), Map.put(new_meta, :request, request),
           state(state, given: new_given)}

        {:reply, response, new_given} ->
          {:reply, response, state(state, given: new_given)}

        {:reply, response, new_given, timeout} ->
          {:reply, response, state(state, given: new_given), timeout}

        {:noreply, new_given} ->
          {:noreply, state(state, given: new_given)}

        {:stop, reason, new_given} ->
          {:stop, reason, state(state, given: new_given)}
      end
    end)
  end

  # TODO: this should be moved out of here
  defp response_to_tuple(%{"success" => true, "output" => result}) do
    {:ok, result}
  end

  defp response_to_tuple(%{"success" => true} = payload) do
    {:ok, Map.delete(payload, "success")}
  end

  defp response_to_tuple(%{"success" => false, "error" => error}) do
    {:error, :invalid_request, error}
  end

  defp response_to_tuple(%{"success" => false} = payload) do
    {:error, :invalid_request, Map.delete(payload, "success")}
  end

  defp response_to_tuple(payload) do
    {:error, :invalid_request, payload}
  end

  @impl true
  def handle_message(response, %{request: request} = _meta, state(mod: mod, given: given) = state) do
    response
    |> mod.on_response(request, given)
    |> handle_mod_callback(state)
    |> handle_mod_callback_reply(request)
  end

  @impl true
  def handle_cast(message, state) do
    handle_async(message, :handle_cast, state)
  end

  @impl true
  def handle_info(
        {:basic_return, _payload, %{correlation_id: request_id} = _meta},
        state(mod: mod, given: given) = state
      ) do
    pop_waiting(request_id, state, fn request, state ->
      request
      |> mod.on_return(given)
      |> handle_mod_callback(state)
      |> handle_mod_callback_reply(request)
    end)
  end

  def handle_info({:request_timeout, request_id}, state(mod: mod, given: given) = state) do
    pop_waiting(request_id, state, fn request, state ->
      request
      |> mod.on_timeout(given)
      |> handle_mod_callback(state)
      |> handle_mod_callback_reply(request)
    end)
  end

  def handle_info(message, state) do
    handle_async(message, :handle_info, state)
  end

  @impl true
  def terminate(reason, state(mod: mod, given: given)) do
    mod.terminate(reason, given)
  end

  # Private functions

  defp handle_request(_payload, _routing_key, _opts, _from, state(channel: nil) = state) do
    {:reply, {:error, :not_connected}, state}
  end

  defp handle_request(payload, routing_key, opts, from, state(mod: mod, given: given) = state) do
    request = Request.start(from, payload, routing_key, opts)

    case mod.before_request(request, given) do
      {:ok, new_given} ->
        send_request(request, state(state, given: new_given))

      {:ok, new_request, new_given} ->
        send_request(new_request, state(state, given: new_given))

      {:reply, response, new_given} ->
        {:reply, response, state(state, given: new_given)}

      {:stop, reason, response, new_given} ->
        {:stop, reason, response, state(state, given: new_given)}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  defp send_request(request, state(mod: mod, given: given) = state) do
    case mod.encode_request(request, given) do
      {:ok, new_request, new_given} ->
        publish(new_request, state(state, given: new_given))

      {:reply, response, new_given} ->
        {:reply, response, state(state, given: new_given)}

      {:reply, response, new_given, timeout} ->
        {:reply, response, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}

      {:stop, reason, response, new_given} ->
        {:stop, reason, response, state(state, given: new_given)}
    end
  end

  defp publish(
         request,
         state(exchange: exchange, queue: queue, channel: channel, timeout: timeout) = state
       ) do
    request =
      request
      |> Request.put_option(:mandatory, true)
      |> Request.put_option(:type, "request")
      |> Request.put_option(:correlation_id, request.id)
      |> Request.put_option(:reply_to, queue.name)
      |> Request.set_timeout(timeout)

    exchange
    |> Exchange.publish(channel, request.payload, request.routing_key, request.options)
    |> after_publish(request, state)
  end

  defp after_publish(:ok, request, state(waiting: waiting) = state) do
    request =
      case Request.get_timeout(request) do
        :infinity ->
          request

        timeout ->
          timer = Process.send_after(self(), {:request_timeout, request.id}, timeout)
          %{request | timer: timer}
      end

    {:noreply, state(state, waiting: Map.put(waiting, request.id, request))}
  end

  defp after_publish(error, _request, state) do
    {:reply, error, state}
  end

  defp handle_mod_callback(response, state) do
    case response do
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

  defp handle_mod_callback_reply(result, request) do
    case result do
      {:reply, response, new_state} ->
        GenServer.reply(request.from, response)

        {:noreply, new_state}

      {:reply, response, new_state, timeout} ->
        GenServer.reply(request.from, response)

        {:noreply, new_state, timeout}

      other ->
        other
    end
  end

  defp handle_async(message, fun, state(mod: mod, given: given) = state) do
    case apply(mod, fun, [message, given]) do
      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  defp pop_waiting(request_id, state(waiting: waiting) = state, func) do
    {request, new_waiting} = Map.pop(waiting, request_id)

    if request do
      if request.timer do
        Process.cancel_timer(request.timer)
      end

      request
      |> Request.finish()
      |> func.(state(state, waiting: new_waiting))
    else
      {:noreply, state}
    end
  end
end
