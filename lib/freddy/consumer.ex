defmodule Freddy.Consumer do
  @moduledoc """
  This module allows to consume messages from specified queue bound to specified exchange.

  ## Configuration

    * `:exchange` - specifies an exchange to declare. See `Freddy.Core.Exchange` for available
      options. Optional.
    * `:queue` - specifies a queue to declare. See `Freddy.Core.Queue` for available options.
      Mandatory.
    * `:qos` - configures channel QoS. See `Freddy.Core.QoS` for available options.
    * `:binds` - specifies bindings to create from the declared queue to the declared
      exchange. Must be a list of keywords or `%Freddy.Core.Bind{}` structs. See `Freddy.Core.Bind`
      for available options.
    * `:routing_keys` - a short way to declare bindings, for example providing a list
      `["key1", "key2"]` is an equivalent of specifying option
      `[binds: [[routing_key: "key1"], [routing_key: "key2"]]]`.
    * `:consumer` - arguments to provide to `basic.consume` method, see below.

  ## Consumer options

    * `:consumer_tag` - Specifies the identifier for the consumer. The consumer tag is
      local to a channel, so two clients can use the same consumer tags. If this field
      is empty the server will generate a unique tag. Default is empty.
    * `:no_local` - If the `:no_local` field is set the server will not send messages
      to the connection that published them. Default is `false`.
    * `:no_ack` - If this field is set the server does not expect acknowledgements for
      messages. That is, when a message is delivered to the client the server assumes
      the delivery will succeed and immediately dequeues it. This functionality may
      increase performance but at the cost of reliability. Messages can get lost if a
      client dies before they are delivered to the application. Defaults to `false`.
    * `:exclusive` - Request exclusive consumer access, meaning only this consumer can
      access the queue. Default is `false`.
    * `:nowait` - If set, the server will not respond to the method and client
      will not wait for a reply. Default is `false`.
    * `:arguments` - A set of arguments for the consume. The syntax and semantics
      of these arguments depends on the server implementation.

  ## Example

      defmodule Notifications.Listener do
        use Freddy.Consumer

        def start_link(conn, initial \\ nil, opts \\ []) do
          config = [
            exchange: [name: "freddy-topic", type: :topic],
            queue: [name: "notifications-queue", opts: [auto_delete: true]],
            qos: [prefetch_count: 10], # optional
            routing_keys: ["routing_key1", "routing_key2"], # short way to declare binds
            binds: [ # fully customizable bindings
              [routing_key: "routing_key3", no_wait: true]
            ],
            consumer: [exclusive: true] # optional
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

  use Freddy.Core.Actor, queue: nil, exchange: nil

  @type routing_key :: String.t()
  @type action :: :ack | :nack | :reject
  @type error :: term
  @type connection_info :: %{
          channel: Freddy.Core.Channel.t(),
          queue: Freddy.Core.Queue.t(),
          exchange: Freddy.Core.Exchange.t()
        }

  @doc """
  Called when the `Freddy.Consumer` process has opened and AMQP channel and declared an exchange and a queue.

  First argument is a map, containing `:channel`, `:exchange` and `:queue` structures.

  Returning `{:noreply, state}` will cause the process to enter the main loop
  with the given state.

  Returning `{:error, state}` will indicate that process failed to perform some critical actions
  and must reconnect.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `c:terminate/2` before the process exits with reason `reason`.
  """
  @callback handle_connected(meta :: connection_info, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:error, state}
              | {:stop, reason :: term, state}

  @doc """
  Called when the AMQP server has registered the process as a consumer and it
  will start to receive messages.

  Returning `{:noreply, state}` will causes the process to enter the main loop
  with the given state.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `terminate(reason, state)` before the process exits with reason `reason`.
  """
  @callback handle_ready(meta, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  @doc """
  Called when a message is delivered from the queue before passing it into a
  `handle_message` function.

  The arguments are the message's raw payload, some metatdata and the internal state.
  The metadata is a map containing all metadata given by the AMQP client when receiving
  the message plus the `:exchange` and `:queue` values.

  Returning `{:ok, payload, state}` or `{:ok, payload, meta, state}` will pass the decoded
  payload and meta into `handle_message/3` function.

  Returning `{:reply, action, opts, state}` or `{:reply, action, state}` will immediately ack,
  nack or reject the message.

  Returning `{:noreply, state}` will do nothing, and therefore the message should
  be acknowledged by using `Freddy.Consumer.ack/2`, `Freddy.Consumer.nack/2` or
  `Freddy.Consumer.reject/2`.

  Returning `{:stop, reason, state}` will terminate the main loop and call
  `terminate(reason, state)` before the process exits with reason `reason`.
  """
  @callback decode_message(payload :: String.t(), meta, state) ::
              {:ok, payload, state}
              | {:ok, payload, meta, state}
              | {:reply, action, opts :: Keyword.t(), state}
              | {:reply, action, state}
              | {:noreply, state}
              | {:stop, reason :: term, state}

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
  `terminate(reason, state)` before the process exits with reason `reason`.
  """
  @callback handle_message(payload, meta, state) ::
              {:reply, action, state}
              | {:reply, action, opts :: Keyword.t(), state}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason :: term, state}

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Freddy.Consumer

      # Default callback implementation

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
      def handle_disconnected(_reason, state) do
        {:noreply, state}
      end

      @impl true
      def decode_message(payload, _meta, state) do
        case Jason.decode(payload) do
          {:ok, new_payload} -> {:ok, new_payload, state}
          {:error, reason} -> {:reply, :reject, [requeue: false], state}
        end
      end

      @impl true
      def handle_message(_message, _meta, state) do
        {:reply, :ack, state}
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
      def terminate(_reason, _state),
        do: :ok

      defoverridable Freddy.Consumer
    end
  end

  alias Freddy.Core.Exchange
  alias Freddy.Core.Queue
  alias Freddy.Core.QoS
  alias Freddy.Core.Bind

  @doc "Ack's a message given its meta"
  @spec ack(meta :: map, opts :: Keyword.t()) :: :ok
  def ack(
        %{channel: %{adapter: adapter, chan: chan}, delivery_tag: delivery_tag} = _meta,
        opts \\ []
      ) do
    adapter.ack(chan, delivery_tag, opts)
  end

  @doc "Nack's a message given its meta"
  @spec nack(meta :: map, opts :: Keyword.t()) :: :ok
  def nack(
        %{channel: %{adapter: adapter, chan: chan}, delivery_tag: delivery_tag} = _meta,
        opts \\ []
      ) do
    adapter.nack(chan, delivery_tag, opts)
  end

  @doc "Rejects a message given its meta"
  @spec reject(meta :: map, opts :: Keyword.t()) :: :ok
  def reject(
        %{channel: %{adapter: adapter, chan: chan}, delivery_tag: delivery_tag} = _meta,
        opts \\ []
      ) do
    adapter.reject(chan, delivery_tag, opts)
  end

  @impl true
  def handle_connected(meta, state(config: config) = state) do
    case declare_subscription(meta, config) do
      {:ok, %{channel: channel, queue: queue, exchange: exchange} = new_meta} ->
        handle_mod_connected(
          new_meta,
          state(state, channel: channel, queue: queue, exchange: exchange)
        )

      {:error, :closed} ->
        {:error, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  defp declare_subscription(%{channel: channel} = meta, config) do
    exchange =
      config
      |> Keyword.get(:exchange, Exchange.default())
      |> Exchange.new()

    queue =
      config
      |> Keyword.fetch!(:queue)
      |> Queue.new()

    qos =
      config
      |> Keyword.get(:qos, QoS.default())
      |> QoS.new()

    routing_keys =
      config
      |> Keyword.get(:routing_keys, [])
      |> Enum.map(&Bind.new(routing_key: &1))

    custom_binds =
      config
      |> Keyword.get(:binds, [])
      |> Enum.map(&Bind.new/1)

    binds = routing_keys ++ custom_binds

    consumer_opts = Keyword.get(config, :consumer, [])

    with :ok <- Exchange.declare(exchange, channel),
         {:ok, queue} <- Queue.declare(queue, channel),
         :ok <- QoS.declare(qos, channel),
         :ok <- Bind.declare_multiple(binds, exchange, queue, channel),
         {:ok, _consumer_tag} <- Queue.consume(queue, self(), channel, consumer_opts) do
      new_meta =
        meta
        |> Map.put(:queue, queue)
        |> Map.put(:exchange, exchange)

      {:ok, new_meta}
    end
  end

  @impl true
  def handle_info(message, state(channel: %{adapter: adapter}) = state) do
    case adapter.handle_message(message) do
      {:consume_ok, meta} ->
        handle_mod_ready(meta, state)

      {:deliver, payload, meta} ->
        handle_delivery(payload, meta, state)

      {:cancel, _meta} ->
        {:stop, :canceled, state}

      {:cancel_ok, _meta} ->
        {:stop, {:shutdown, :canceled}, state}

      {:return, _payload, _meta} = message ->
        super(message, state)

      :unknown ->
        super(message, state)
    end
  end

  def handle_info(message, state) do
    super(message, state)
  end

  defp handle_mod_ready(meta, state(mod: mod, given: given) = state) do
    case mod.handle_ready(complete(meta, state), given) do
      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  @reply_actions [:ack, :nack, :reject]

  defp handle_delivery(payload, meta, state(mod: mod, given: given) = state) do
    meta = complete(meta, state)

    result =
      case mod.decode_message(payload, meta, given) do
        {:ok, new_payload, new_given} ->
          mod.handle_message(new_payload, meta, new_given)

        {:ok, new_payload, new_meta, new_given} ->
          mod.handle_message(new_payload, new_meta, new_given)

        other ->
          other
      end

    case result do
      {:reply, action, new_given} when action in @reply_actions ->
        apply(__MODULE__, action, [meta])
        {:noreply, state(state, given: new_given)}

      {:reply, action, opts, new_given} when action in @reply_actions ->
        apply(__MODULE__, action, [meta, opts])
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given} ->
        {:noreply, state(state, given: new_given)}

      {:noreply, new_given, timeout} ->
        {:noreply, state(state, given: new_given), timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, state(state, given: new_given)}
    end
  end

  defp complete(meta, state(channel: channel, queue: queue, exchange: exchange)) do
    meta
    |> Map.put(:exchange, exchange)
    |> Map.put(:queue, queue)
    |> Map.put(:channel, channel)
  end
end
