defmodule Freddy.Consumer do
  @moduledoc """
  This module allows to consume messages from specified queue bound to specified exchange.

  Example:

    defmodule Notifications.Listener do
      use Freddy.Consumer

      def start_link(conn, initial \\ nil, opts \\ []) do
        config = [
          exchange: [name: "freddy-topic", type: :topic],
          queue: [name: "notifications-queue", opts: [auto_delete: true]],
          routing_keys: ["routing_key1", "routing_key2"], # short way to declare binds
          binds: [ # fully customizable bindings
            [routing_key: "routing_key3", no_wait: true]
          ]
        ]
        Freddy.Consumer.start_link(__MODULE__, conn, config, initial, opts)
      end

      def init(initial) do
        # do something on init
        {:ok, initial}
      end

      def handle_message(payload, %{routing_key: "visitor.status.disconnect"}, state) do
        {:reply, :ack, state}
      end

      def handle_error(error, message, _meta) do
        # log error?
        {:reply, :nack, state}
      end
    end
  """

  @type payload :: term
  @type meta    :: map
  @type action  :: :ack | :nack | :reject
  @type state   :: term
  @type error   :: term

  @doc """
  Called when the consumer process is first started.

  Returning `{:ok, state}` will cause `start_link/3` to return `{:ok, pid}` and attempt to
  open a channel on the given connection and declare the queue, the exchange, and the bindings
  to the specified routing keys.

  After that it will enter the main loop with `state` as its internal state.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the
  process will exit normally without entering the loop, opening a channel or calling
  `terminate/2`.

  Returning `{:stop, reason}` will cause `start_link/3` to return `{:error, reason}` and
  the process will exit with reason `reason` without entering the loop, opening a channel,
  or calling `terminate/2`.
  """
  @callback init(state) ::
              {:ok, state} |
              :ignore |
              {:stop, reason :: term}

  @doc """
  Called when the AMQP server has registered the process as a consumer and it
  will start to receive messages.

  Returning `{:noreply, state}` will causes the process to enter the main loop
  with the given state.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `terminate(reason, state)` before the process exists with reason `reason`.
  """
  @callback handle_ready(meta, state) ::
              {:noreply, state} |
              {:stop, reason :: term, state}

  @doc """
  Called when a message is delivered from the queue.

  The arguments are the message's decoded payload, some metadata and the internal state.
  The metadata is a map containing all metadata given by the adapter when receiving
  the message plus the `:exchange` and `:queue` values received at the `connect/2`
  callback.

  Returning `{:reply, :ack | :nack | :reject, state}` will ack, nack or reject
  the message.

  Returning `{:reply, :ack | :nack | :reject, opts, state}` will ack, nack or reject
  the message with the given opts.

  Returning `{:noreply, state}` will do nothing, and therefore the message should
  be acknowledged by using `Freddy.Consumer.ack/2`, `Freddy.Consumer.nack/2` or
  `Freddy.Consumer.reject/2`.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `terminate(reason, state)` before the process exists with reason `reason`.
  """
  @callback handle_message(payload, meta, state) ::
              {:reply, action, state} |
              {:reply, action, opts :: Keyword.t, state} |
              {:noreply, state} |
              {:stop, reason :: term, state}

  @doc """
  Called when a message cannot be decoded or when an error occurred during message processing.

  The arguments are the error, the message's original payload, some metadata and the internal state.
  The metadata is a map containing all metadata given by the adapter when receiving
  the message plus the `:exchange` and `:queue` values received at the `connect/2`
  callback.

  Returning `{:reply, :ack | :nack | :reject, state}` will ack, nack or reject
  the message.

  Returning `{:reply, :ack | :nack | :reject, opts, state}` will ack, nack or reject
  the message with the given opts.

  Returning `{:noreply, state}` will do nothing, and therefore the message should
  be acknowledged by using `Freddy.Consumer.ack/2`, `Freddy.Consumer.nack/2` or
  `Freddy.Consumer.reject/2`.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `terminate(reason, state)` before the process exists with reason `reason`.
  """
  @callback handle_error(error, payload, meta, state) ::
              {:reply, action, state} |
              {:reply, action, opts :: Keyword.t, state} |
              {:noreply, state} |
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
  Called when the process receives a message.

  Returning `{:noreply, state}` will causes the process to enter the main loop
  with the given state.

  Returning `{:stop, reason, state}` will not send the message, terminate the
  main loop and call `terminate(reason, state)` before the process exists with
  reason `reason`.
  """
  @callback handle_info(term, state) ::
              {:noreply, state} |
              {:stop, reason :: term, state}


  @doc """
  This callback is the same as the `GenServer` equivalent and is called when the
  process terminates. The first argument is the reason the process is about
  to exit with.
  """
  @callback terminate(reason :: term, state) ::
              any

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Freddy.Consumer

      # Default callback implementation

      @doc false
      def init(initial),
        do: {:ok, initial}

      @doc false
      def handle_ready(_meta, state),
        do: {:noreply, state}

      @doc false
      def handle_message(_message, _meta, state),
        do: {:reply, :ack, state}

      @doc false
      def handle_error(_error, _payload, _meta, state),
        do: {:reply, :reject, state}

      @doc false
      def handle_call(message, _from, state),
        do: {:stop, {:bad_call, message}, state}

      @doc false
      def handle_cast(_message, state),
        do: {:noreply, state}

      @doc false
      def handle_info(_message, state),
        do: {:noreply, state}

      @doc false
      def terminate(_reason, _state),
        do: :ok

      defoverridable [init: 1, handle_ready: 2,
                      handle_message: 3, handle_info: 2, handle_error: 4,
                      terminate: 2]
    end
  end

  use Hare.Consumer

  @type config :: [queue:        Hare.Context.Action.DeclareQueue.config,
                   exchange:     Hare.Context.Action.DeclareExchange.config,
                   routing_keys: [String.t],
                   binds:        [Keyword.t]]

  @type connection :: GenServer.server

  @compile {:inline, start_link: 4, start_link: 5, stop: 1, stop: 2}

  @doc """
  Start a `Freddy.Consumer` process linked to the current process.

  Arguments:

    * `mod` - the module that defines the server callbacks (like GenServer)
    * `connection` - the pid of a `Hare.Core.Conn` process
    * `config` - the configuration of the consumer
    * `initial` - the value that will be given to `init/1`
    * `opts` - the GenServer options
  """
  @spec start_link(module, connection, config, initial :: term, GenServer.options) :: GenServer.on_start
  def start_link(mod, connection, config, initial, opts \\ []) do
    Hare.Consumer.start_link(__MODULE__, connection, build_consumer_config(config), {mod, initial}, opts)
  end

  defdelegate stop(consumer, reason \\ :normal), to: GenServer
  defdelegate ack(meta, opts \\ []), to: Hare.Consumer
  defdelegate nack(meta, opts \\ []), to: Hare.Consumer
  defdelegate reject(meta, opts \\ []), to: Hare.Consumer

  # Hare.Consumer callbacks implementation

  @doc false
  def init({mod, initial}) do
    case mod.init(initial) do
      {:ok, state} -> {:ok, {mod, state}}
      :ignore -> :ignore
      {:stop, reason} -> {:stop, reason}
    end
  end

  @doc false
  def handle_ready(meta, {mod, state}) do
    case mod.handle_ready(meta, state) do
      {:noreply, new_state} -> {:noreply, {mod, new_state}}
      {:stop, reason, new_state} -> {:stop, reason, {mod, new_state}}
    end
  end

  @doc false
  def handle_message(payload, meta, {mod, state}) do
    case Poison.decode(payload) do
      {:ok, decoded} -> handle_mod_message(decoded, meta, mod, state)
      error -> handle_mod_error(error, payload, meta, mod, state)
    end
  end

  @doc false
  def handle_call(message, from, {mod, state}) do
    case mod.handle_call(message, from, state) do
      {:reply, reply, new_state} -> {:reply, reply, {mod, new_state}}
      {:reply, reply, new_state, timeout} -> {:reply, reply, {mod, new_state}, timeout}
      {:noreply, new_state} -> {:noreply, {mod, new_state}}
      {:noreply, new_state, timeout} -> {:noreply, {mod, new_state}, timeout}
      {:stop, reason, new_state} -> {:stop, reason, {mod, new_state}}
      {:stop, reason, reply, new_state} -> {:stop, reason, reply, {mod, new_state}}
    end
  end

  @doc false
  def handle_cast(message, {mod, state}) do
    case mod.handle_cast(message, state) do
      {:noreply, new_state} -> {:noreply, {mod, new_state}}
      {:noreply, new_state, timeout} -> {:noreply, {mod, new_state}, timeout}
      {:stop, reason, new_state} -> {:stop, reason, {mod, new_state}}
    end
  end

  @doc false
  def handle_info(meta, {mod, state}) do
    meta
    |> mod.handle_info(state)
    |> handle_mod_response(mod)
  end

  @doc false
  def terminate(reason, {mod, state}),
    do: mod.terminate(reason, state)

  defp handle_mod_message(message, meta, mod, state) do
    message
    |> mod.handle_message(meta, state)
    |> handle_mod_response(mod)
  end

  defp handle_mod_error(error, payload, meta, mod, state) do
    error
    |> mod.handle_error(payload, meta, state)
    |> handle_mod_response(mod)
  end

  @reply_actions [:ack, :nack, :reject]

  defp handle_mod_response(response, mod) do
    case response do
      {:reply, action, state} when action in @reply_actions ->
        {:reply, action, {mod, state}}

      {:reply, action, options, state} when action in @reply_actions ->
        {:reply, action, options, {mod, state}}

      {:noreply, state} ->
        {:noreply, {mod, state}}

      {:stop, reason, state} ->
        {:stop, reason, {mod, state}}
    end
  end

  defp build_consumer_config(config) do
    queue = Keyword.fetch!(config, :queue)
    exchange = Keyword.fetch!(config, :exchange)

    routing_keys =
      config
      |> Keyword.get(:routing_keys, [])
      |> Enum.map(&{:bind, [routing_key: &1]})

    custom_binds =
      config
      |> Keyword.get(:binds, [])
      |> Enum.map(&{:bind, &1})

    [
      queue: queue,
      exchange: exchange
    ] ++ routing_keys ++ custom_binds
  end
end
