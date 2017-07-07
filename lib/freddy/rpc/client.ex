defmodule Freddy.RPC.Client do
  @moduledoc ~S"""
  This module allows to build RPC client for any Freddy-compliant microservice.

  Example:

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

  @type payload     :: term
  @type request     :: Freddy.RPC.Request.t
  @type response    :: term
  @type routing_key :: Hare.Adapter.routing_key
  @type opts        :: Hare.Adapter.opts
  @type meta        :: map
  @type state       :: term

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
  `terminate/2`.

  Returning `{:stop, reason}` will cause `start_link/5` to return `{:error, reason}` and
  the process will exit with reason `reason` without entering the loop, opening a channel,
  or calling `terminate/2`.
  """
  @callback init(initial :: term) ::
              {:ok, state} |
              :ignore |
              {:stop, reason :: term}


  @doc """
  Called when the AMQP server has registered the process as a consumer of the
  server-named queue and it will start to receive messages.

  Returning `{:noreply, state}` will causes the process to enter the main loop
  with the given state.

  Returning `{:stop, reason, state}` will not send the message, terminate the
  main loop and call `terminate(reason, state)` before the process exits with
  reason `reason`.
  """
  @callback handle_ready(meta, state) ::
              {:noreply, state} |
              {:stop, reason :: term, state}

  @doc """
  Called before a request will be performed to the exchange.

  It receives as argument the RPC request structure which contains the message
  payload, the routing key and the options for that publication, and the
  internal client state.

  Returning `{:ok, state}` will cause the request to be performed with no
  modification, block the client until the response is received, and enter
  the main loop with the given state.

  Returning `{:ok, request, state}` will do the same as `{:ok, state}`, but
  returned `meta` will be given as a 2nd argument in `on_response/3` and
  as a 1st argument in `on_timeout/3` callback.

  Returning `{:ok, request, state}` will cause the payload, routing key and
  options from the given `request` to be used instead or the original ones,
  block the client until the response is received, and enter the main loop
  with the given state.

  Returning `{:reply, response, state}` will respond the client inmediately
  without performing the request with the given response, and enter the main
  loop again with the given state.

  Returning `{:stop, reason, response, state}` will not send the message,
  respond to the caller with `response`, and terminate the main loop
  and call `terminate(reason, state)` before the process exits with
  reason `reason`.

  Returning `{:stop, reason, state}` will not send the message, terminate the
  main loop and call `terminate(reason, state)` before the process exits with
  reason `reason`.
  """
  @callback before_request(request, state) ::
              {:ok, state} |
              {:ok, request, state} |
              {:reply, response, state} |
              {:stop, reason :: term, response, state} |
              {:stop, reason :: term, state}

  @doc """
  Called when a response has been received, before it is delivered to the caller.

  It receives as argument the message payload, the routing key, the options
  for that publication, the response, and the internal state.

  Returning `{:reply, reply, state}` will cause the given reply to be
  delivered to the caller instead of the original response, and enter
  the main loop with the given state.

  Returning `{:noreply, state}` will enter the main loop with the given state
  without responding to the caller (that will eventually timeout or keep blocked
  forever if the timeout was set to `:infinity`).

  Returning `{:stop, reason, reply, state}` will deliver the given reply to
  the caller instead of the original response and call `terminate(reason, state)`
  before the process exits with reason `reason`.

  Returning `{:stop, reason, state}` not reply to the caller and call
  `terminate(reason, state)` before the process exits with reason `reason`.
  """
  @callback on_response(response, request, state) ::
              {:reply, response, state} |
              {:reply, response, state, timeout | :hibernate} |
              {:noreply, state} |
              {:noreply, state, timeout | :hibernate} |
              {:stop, reason :: term, response, state} |
              {:stop, reason :: term, state}

  @doc """
  Called when a request has timed out.

  Returning `{:reply, reply, state}` will cause the given reply to be
  delivered to the caller, and enter the main loop with the given state.

  Returning `{:noreply, state}` will enter the main loop with the given state
  without responding to the caller (that will eventually timeout or keep blocked
  forever if the timeout was set to `:infinity`).

  Returning `{:stop, reason, reply, state}` will deliver the given reply to
  the caller, and call `terminate(reason, state)` before the process exits
  with reason `reason`.

  Returning `{:stop, reason, state}` will not reply to the caller and call
  `terminate(reason, state)` before the process exits with reason `reason`.
  """
  @callback on_timeout(request, state) ::
              {:reply, response, state} |
              {:reply, response, state, timeout | :hibernate} |
              {:noreply, state} |
              {:noreply, state, timeout | :hibernate} |
              {:stop, reason :: term, response, state} |
              {:stop, reason :: term, state}

  @doc """
  Called when a request has been returned by AMPQ broker.

  Returning `{:reply, reply, state}` will cause the given reply to be
  delivered to the caller, and enter the main loop with the given state.

  Returning `{:noreply, state}` will enter the main loop with the given state
  without responding to the caller (that will eventually timeout or keep blocked
  forever if the timeout was set to `:infinity`).

  Returning `{:stop, reason, reply, state}` will deliver the given reply to
  the caller, and call `terminate(reason, state)` before the process exits
  with reason `reason`.

  Returning `{:stop, reason, state}` will not reply to the caller and call
  `terminate(reason, state)` before the process exits with reason `reason`.
  """
  @callback on_return(request, state) ::
              {:reply, response, state} |
              {:reply, response, state, timeout | :hibernate} |
              {:noreply, state} |
              {:noreply, state, timeout | :hibernate} |
              {:stop, reason :: term, response, state} |
              {:stop, reason :: term, state}

  @doc """
  Called when the process receives a call message sent by `call/3`. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:reply`, `:noreply` and `:stop` return tuples behave the same.
  """
  @callback handle_call(request :: term, GenServer.from, state) ::
              {:reply, reply :: term, state} |
              {:reply, reply :: term, state, timeout | :hibernate} |
              {:noreply, state} |
              {:noreply, state, timeout | :hibernate} |
              {:stop, reason :: term, state} |
              {:stop, reason :: term, reply :: term, state}

  @doc """
  Called when the process receives a cast message sent by `cast/3`. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:noreply` and `:stop` return tuples behave the same.
  """
  @callback handle_cast(request :: term, state) ::
              {:noreply, state} |
              {:noreply, state, timeout | :hibernate} |
              {:stop, reason :: term, state}

  @doc """
  Called when the process receives a message. This callback has the same
  arguments as the `GenServer` equivalent and the `:noreply` and `:stop`
  return tuples behave the same.
  """
  @callback handle_info(message :: term, state) ::
              {:noreply, state} |
              {:noreply, state, timeout | :hibernate} |
              {:stop, reason :: term, state}

  @doc """
  This callback is the same as the `GenServer` equivalent and is called when the
  process terminates. The first argument is the reason the process is about
  to exit with.
  """
  @callback terminate(reason :: term, state) ::
              any

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      @behaviour Freddy.RPC.Client

      @doc false
      def init(initial),
        do: {:ok, initial}

      @doc false
      def handle_ready(_meta, state),
        do: {:noreply, state}

      @doc false
      def before_request(_request, state),
        do: {:ok, state}

      @doc false
      def on_response(response, _request, state),
        do: {:reply, response, state}

      @doc false
      def on_timeout(_request, state),
        do: {:reply, {:error, :timeout}, state}

      def on_return(_request, state),
        do: {:reply, {:error, :no_route}, state}

      @doc false
      def handle_call(message, _from, state),
        do: {:stop, {:bad_call, message}, state}

      @doc false
      def handle_cast(message, state),
        do: {:stop, {:bad_cast, message}, state}

      @doc false
      def handle_info(_message, state),
        do: {:noreply, state}

      @doc false
      def terminate(_reason, _state),
        do: :ok

      defoverridable [init: 1, terminate: 2,
                      handle_ready: 2, before_request: 2,
                      on_response: 3, on_timeout: 2, on_return: 2,
                      handle_call: 3, handle_cast: 2, handle_info: 2]
    end
  end

  use Hare.RPC.Client

  require Logger

  alias Freddy.RPC.Client.State
  alias Freddy.RPC.Request

  @default_timeout 3000
  @gen_server_timeout 10000

  @type config :: [timeout: timeout,
                   exchange: Hare.Context.Action.DeclareExchange.config]

  @doc """
  Starts a `Freddy.RPC.Client` process linked to the current process.

  This function is used to start a `Freddy.RPC.Client` process in a supervision
  tree. The process will be started by calling `init` with the given initial
  value.

  Arguments:

    * `mod` - the module that defines the server callbacks (like GenServer)
    * `conn` - the pid of a `Hare.Core.Conn` process
    * `config` - the configuration of the RPC Client (describing the exchange, routing_key and timeout value)
    * `initial` - the value that will be given to `init/1`
    * `opts` - the GenServer options
  """
  @spec start_link(module, GenServer.server, config, initial :: term, GenServer.options) ::
          GenServer.on_start |
          no_return()
  def start_link(mod, conn, config, initial, opts \\ []) do
    exchange = Keyword.get(config, :exchange, [])
    timeout = Keyword.get(config, :timeout, @default_timeout)

    Hare.RPC.Client.start_link(
      __MODULE__,
      conn,
      [exchange: exchange, timeout: timeout],
      {mod, timeout, initial},
      opts
    )
  end

  defdelegate call(client, message),           to: Hare.RPC.Client
  defdelegate call(client, message, timeout),  to: Hare.RPC.Client
  defdelegate cast(client, message),           to: Hare.RPC.Client
  defdelegate stop(client, reason \\ :normal), to: GenServer

  @doc """
  Performs a RPC request and blocks until the response arrives.
  """
  @spec request(GenServer.server, routing_key, payload, GenServer.options) ::
          {:ok, response} |
          {:error, reason :: term} |
          {:error, reason :: term, hint :: term}
  def request(client, routing_key, payload, opts \\ []) do
    Hare.Actor.call(client, {:"$hare_request", payload, routing_key, opts}, @gen_server_timeout)
  end

  # Hare.RPC.Client callbacks

  @doc false
  def init({mod, timeout, initial}) do
    case mod.init(initial) do
      {:ok, given} -> {:ok, State.new(mod, timeout, given)}
      {:stop, reason} -> {:stop, reason}
      :ignore -> :ignore
    end
  end

  @doc false
  def handle_ready(meta, %{mod: mod, given: given} = state) do
    case mod.handle_ready(meta, given) do
      {:noreply, new_given} -> {:noreply, State.update(state, new_given)}
      {:stop, reason, new_given} -> {:stop, reason, State.update(state, new_given)}
    end
  end

  @doc false
  def before_request(payload, routing_key, opts, from, %{mod: mod, given: given} = state) do
    request = Request.start(from, payload, routing_key, opts)

    case mod.before_request(request, given) do
      {:ok, new_given} ->
        send_request(request, new_given, state)

      {:ok, new_request, new_given} ->
        send_request(new_request, new_given, state)

      {:reply, response, new_given} ->
        {:reply, response, State.update(state, new_given)}

      {:stop, reason, response, new_given} ->
        {:stop, reason, response, State.update(state, new_given)}

      {:stop, reason, new_given} ->
        {:stop, reason, State.update(state, new_given)}
    end
  end

  defp send_request(%{payload: payload, routing_key: routing_key, options: options} = request, new_given, state) do
    case Poison.encode(payload) do
      {:ok, encoded_payload} ->
        freddy_options = [mandatory: true,
                          content_type: "application/json",
                          expiration: to_string(state.timeout),
                          type: "request"]

        options = Keyword.merge(options, freddy_options)
        new_state = state |> State.update(new_given) |> State.push_waiting(request)

        Logger.debug fn -> "Sending request to #{routing_key}: #{encoded_payload}" end

        {:ok, encoded_payload, routing_key, options, new_state}

      {:error, reason} ->
        {:stop, {:encode_error, reason}, State.update(state, new_given)}
    end
  end

  @doc false
  def on_response(response, from, %{mod: mod, given: given} = state) do
    case State.pop_waiting(state, from) do
      {:ok, request, new_state} ->
        finished_request = Request.finish(request)

        response
        |> log_response(finished_request)
        |> Poison.decode()
        |> handle_response()
        |> mod.on_response(finished_request, given)
        |> handle_mod_callback(new_state)

      {:error, :not_found} ->
        {:noreply, state}
    end
  end

  @doc false
  def on_timeout(from, %{mod: mod, given: given} = state) do
    case State.pop_waiting(state, from) do
      {:ok, request, new_state} ->
        finished_request = Request.finish(request)

        log_timeout(finished_request)

        finished_request
        |> mod.on_timeout(given)
        |> handle_mod_callback(new_state)

      {:error, :not_found} ->
        {:noreply, state}
    end
  end

  @doc false
  def on_return(from, %{mod: mod, given: given} = state) do
    case State.pop_waiting(state, from) do
      {:ok, request, new_state} ->
        finished_request = Request.finish(request)

        log_return(finished_request)

        finished_request
        |> mod.on_return(given)
        |> handle_mod_callback(new_state)

      {:error, :not_found} ->
        {:noreply, state}
    end
  end

  @doc false
  def handle_call(message, from, %{mod: mod, given: given} = state) do
    case mod.handle_call(message, from, given) do
      {:reply, reply, new_given} ->
        {:reply, reply, State.update(state, new_given)}

      {:reply, reply, new_given, timeout} ->
        {:reply, reply, State.update(state, new_given), timeout}

      {:noreply, new_given} ->
        {:noreply, State.update(state, new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, State.update(state, new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, State.update(state, new_given)}

      {:stop, reason, reply, new_given} ->
        {:stop, reason, reply, State.update(state, new_given)}
    end
  end

  @doc false
  def handle_cast(message, state) do
    handle_async(message, :handle_cast, state)
  end

  @doc false
  def handle_info(message, state) do
    handle_async(message, :handle_info, state)
  end

  @doc false
  def terminate(reason, %{mod: mod, given: given}) do
    mod.terminate(reason, given)
  end

  # Private functions

  defp handle_mod_callback(response, state) do
    case response do
      {:reply, response, new_given} ->
        {:reply, response, State.update(state, new_given)}

      {:reply, response, new_given, timeout} ->
        {:reply, response, State.update(state, new_given), timeout}

      {:noreply, new_given} ->
        {:noreply, State.update(state, new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, State.update(state, new_given), timeout}

      {:stop, reason, response, new_given} ->
        {:stop, reason, response, State.update(state, new_given)}

      {:stop, reason, new_given} ->
        {:stop, reason, State.update(state, new_given)}
    end
  end

  defp handle_async(message, fun, %{mod: mod, given: given} = state) do
    case apply(mod, fun, [message, given]) do
      {:noreply, new_given} ->
        {:noreply, State.update(state, new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, State.update(state, new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, State.update(state, new_given)}
    end
  end

  defp handle_response({:ok, %{"success" => true, "output" => result}}),
    do: {:ok, result}
  defp handle_response({:ok, %{"success" => true} = payload}),
    do: {:ok, Map.delete(payload, "success")}
  defp handle_response({:ok, %{"success" => false, "error" => error}}),
    do: {:error, :invalid_request, error}
  defp handle_response({:ok, %{"success" => false} = payload}),
    do: {:error, :invalid_request, Map.delete(payload, "success")}
  defp handle_response({:ok, payload}),
    do: {:error, :invalid_request, payload}
  defp handle_response({:error, json_error}),
    do: {:error, :protocol_error, json_error}

  defp log_response(response, %{routing_key: routing_key} = request) do
    Logger.debug fn ->
      ["Response received from ", routing_key, " after #{Request.duration(request)} ms:", response]
    end

    response
  end

  defp log_timeout(%{routing_key: routing_key} = request),
    do: Logger.error fn -> ["RPC call to ", routing_key, " timed out after #{Request.duration(request)} ms"] end

  defp log_return(%{routing_key: routing_key} = _request),
    do: Logger.error fn -> ["RPC call to ", routing_key, " couldn't be routed"] end
end
