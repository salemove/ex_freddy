defmodule Freddy.RPC.Client do
  @moduledoc ~S"""
  This module allows to build RPC client for any Freddy-compliant microservice.

  Example:

    defmodule Tracktor do
      use Freddy.RPC.Client

      @config [routing_key: "Tracktor", timeout: 3500]

      def start_link(conn, initial, opts \\ []) do
        Freddy.RPC.Client.start_link(__MODULE__, conn, @config, initial, opts)
      end
    end

    {:ok, client} = Tracktor.start_link()
    Tracktor.request(client, %{type: "get_operators", site_id: "xxx"})
  """

  @type payload     :: term
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
  main loop and call `terminate(reason, state)` before the process exists with
  reason `reason`.
  """
  @callback handle_ready(meta, state) ::
              {:noreply, state} |
              {:stop, reason :: term, state}

  @doc """
  Called before a request will be performed to the exchange.

  It receives as argument the message payload, the routing key, the options
  for that publication and the internal state.

  Returning `{:ok, state}` will cause the request to be performed with no
  modification, block the client until the response is received, and enter
  the main loop with the given state.

  Returnung `{:ok, meta, state}` will do the same as `{:ok, state}`, but
  returned `meta` will be given as a 2nd argument in `on_response/3` and
  as a 1st argument in `on_timeout/3` callback.

  Returning `{:ok, payload, opts, state}` will cause the
  given payload, routing key and options to be used instead of the original
  ones, block the client until the response is received, and enter
  the main loop with the given state.

  Returning `{:ok, payload, opts, meta, state` will do the same as
  `{:ok, payload, opts, state}`, but returned `meta` will be given as a
  2nd argument in `on_response/3` and as a 1st argument in `on_timeout/3` callback.

  Returning `{:reply, response, state}` will respond the client inmediately
  without performing the request with the given response, and enter the main
  loop again with the given state.

  Returning `{:stop, reason, response, state}` will not send the message,
  respond to the caller with `response`, and terminate the main loop
  and call `terminate(reason, state)` before the process exists with
  reason `reason`.

  Returning `{:stop, reason, state}` will not send the message, terminate the
  main loop and call `terminate(reason, state)` before the process exists with
  reason `reason`.
  """
  @callback before_request(payload, opts :: term, state) ::
              {:ok, state} |
              {:ok, meta, state} |
              {:ok, payload, opts :: term, state} |
              {:ok, payload, opts :: term, meta, state} |
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
  before the process exists with reason `reason`.

  Returning `{:stop, reason, state}` not reply to the caller and call
  `terminate(reason, state)` before the process exists with reason `reason`.
  """
  @callback on_response(response, meta, state) ::
              {:reply, response, state} |
              {:noreply, state} |
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
  the caller, and call `terminate(reason, state)` before the process exists
  with reason `reason`.

  Returning `{:stop, reason, state}` will not reply to the caller and call
  `terminate(reason, state)` before the process exists with reason `reason`.
  """
  @callback on_timeout(meta :: term, state) ::
              {:reply, response, state} |
              {:noreply, state} |
              {:stop, reason :: term, response, state} |
              {:stop, reason :: term, state}

  @doc """
  Called when the process receives a message.

  Returning `{:noreply, state}` will causes the process to enter the main loop
  with the given state.

  Returning `{:stop, reason, state}` will not send the message, terminate the
  main loop and call `terminate(reason, state)` before the process exists with
  reason `reason`.
  """
  @callback handle_info(message :: term, state) ::
              {:noreply, state} |
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

      def before_request(_payload, _opts, state),
        do: {:ok, state}

      def on_response(response, _meta, state),
        do: {:reply, response, state}

      def on_timeout(_meta, state),
        do: {:reply, {:error, :timeout}, state}

      def handle_info(_message, state),
        do: {:noreply, state}

      def terminate(_reason, _state),
        do: :ok

      defoverridable [init: 1, terminate: 2,
                      handle_ready: 2, before_request: 3,
                      on_response: 3, on_timeout: 2, handle_info: 2]
    end
  end

  @behaviour Hare.RPC.Client

  require Logger
  alias Freddy.RPC.Client.State

  @default_timeout 3000
  @gen_server_timeout 10000

  @type config :: [timeout: timeout,
                   exchange: Hare.Context.Action.DeclareExchange.config,
                   routing_key: routing_key]

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
    routing_key = Keyword.fetch!(config, :routing_key)
    timeout = Keyword.get(config, :timeout, @default_timeout)

    Hare.RPC.Client.start_link(
      __MODULE__,
      conn,
      [exchange: exchange, timeout: timeout],
      {mod, timeout, routing_key, initial},
      opts
    )
  end

  defdelegate stop(client, reason \\ :normal), to: GenServer

  @doc """
  Performs a RPC request and blocks until the response arrives.
  """
  @spec request(GenServer.server, payload, GenServer.options) :: response
  def request(client, payload, opts \\ []) do
    Hare.RPC.Client.request(client, payload, "", opts, @gen_server_timeout)
  end

  # Hare.RPC.Client callbacks

  @doc false
  def init({mod, timeout, routing_key, initial}) do
    case mod.init(initial) do
      {:ok, given} -> {:ok, State.new(mod, timeout, routing_key, given)}
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
  def before_request(payload, _, opts, from, %{mod: mod, given: given} = state) do
    freddy_opts = [
      mandatory: true,
      content_type: "application/json",
      expiration: to_string(state.timeout),
      type: "request"
    ]

    case mod.before_request(payload, opts, given) do
      {:ok, new_given} ->
        {:ok,
          Poison.encode!(payload),
          state.routing_key,
          opts ++ freddy_opts,
          state |> State.update(new_given) |> State.push_waiting(from, %{})}

      {:ok, meta, new_given} ->
        {:ok,
          Poison.encode!(payload),
          state.routing_key,
          opts ++ freddy_opts,
          state |> State.update(new_given) |> State.push_waiting(from, meta)}

      {:ok, new_payload, new_opts, new_given} ->
        {:ok,
          Poison.encode!(new_payload),
          state.routing_key,
          new_opts ++ freddy_opts,
          state |> State.update(new_given) |> State.push_waiting(from, %{})}

      {:ok, new_payload, new_opts, meta, new_given} ->
        {:ok,
          Poison.encode!(new_payload),
          state.routing_key,
          new_opts ++ freddy_opts,
          state |> State.update(new_given) |> State.push_waiting(from, meta)}

      {:reply, response, new_given} ->
        {:reply, response, State.update(state, new_given)}

      {:stop, reason, response, new_given} ->
        {:stop, reason, response, State.update(state, new_given)}

      {:stop, reason, new_given} ->
        {:stop, reason, State.update(state, new_given)}
    end
  end

  @doc false
  def on_response(response, from, %{mod: mod, given: given} = state) do
    {meta, new_state} = State.pop_waiting(state, from)

    response
    |> log_response(meta, state)
    |> Poison.decode()
    |> handle_response()
    |> mod.on_response(meta, given)
    |> handle_mod_callback(new_state)
  end

  @doc false
  def on_timeout(from, %{mod: mod, given: given} = state) do
    {meta, new_state} = State.pop_waiting(state, from)

    log_timeout(meta, new_state)

    given
    |> mod.on_timeout(meta)
    |> handle_mod_callback(new_state)
  end

  @doc false
  def handle_info(message, %{mod: mod, given: given} = state) do
    case mod.handle_info(message, given) do
      {:noreply, new_given} -> {:noreply, State.update(state, new_given)}
      {:stop, reason, new_given} -> {:stop, reason, State.update(state, new_given)}
    end
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

      {:noreply, new_given} ->
        {:noreply, State.update(state, new_given)}

      {:stop, reason, response, new_given} ->
        {:stop, reason, response, State.update(state, new_given)}

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

  defp log_response(response, meta, %{routing_key: queue}) do
    Logger.debug fn ->  ["Response received from ", queue, " after #{calculate_elapsed(meta)} ms:", response] end
    response
  end

  defp log_timeout(meta, %{routing_key: queue}),
    do: Logger.error fn -> ["RPC call to ", queue, " timed out after #{calculate_elapsed(meta)} ms"] end

  defp calculate_elapsed(%{start_time: start_time, stop_time: stop_time}),
    do: System.convert_time_unit(stop_time - start_time, :native, :milliseconds)
  defp calculate_elapsed(_),
    do: :unknown
end
