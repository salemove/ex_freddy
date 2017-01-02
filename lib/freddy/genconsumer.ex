defmodule Freddy.GenConsumer do
  @moduledoc ~S"""
  A behaviour module for implementing an AMQP consumer.

  A Freddy.GenConsumer is a process that can be used to keep state and
  provides a standard interface to execute code asynchronously when
  a message is received from the AMQP broker.

  It is based on a GenServer therefore include functionality for tracing
  and error reporting. It will also fit in a supervision tree.

  The Freddy.GenConsumer behaviour abstracts the common broker-consumer
  interaction. Developers are only required to implement the callbacks
  and functionality they are interested in:

    * `queue_spec(options)`

    * `handle_ready(meta, state)

    * `handle_message(payload, meta, state)`

    * `handle_exception(exception, state)`

  Other callbacks from `Freddy.GenQueue` and `Connection` are also available.

  # Example

    ```elixir
    defmodule Printer do
      use Freddy.GenConsumer

      # This is how you can override some queue options.
      def queue_opts(opts) do
        name = opts[:name]
        {name, [manual_ack: true, exclusive: true]}
      end

      def handle_ready(_meta = %{consumer_tag: tag}, state = %{queue: queue}) do
        IO.puts "Consuming messages on #{queue}, tag: #{tag}"
        {:noreply, state}
      end

      # This callback will be invoked on every consumed message.
      def handle_message(payload, _meta, state) do
        IO.puts "Message received: #{payload}"
        {:ack, state}
      end

      # In case if exception happened in handle_message/3, the message
      # will be rejected with option `requeue: false`.
      #
      # See AMQP.Basic.reject/3.
      def handle_exception(_exception, state) do
        {:reject, [requeue: false], state}
      end
    end
    ```

  """

  alias Freddy.GenQueue

  @callback queue_spec(GenQueue.options) ::
    { name :: String.t, options :: Keyword.t }

  @callback handle_ready(meta, state) :: on_callback

  @callback handle_message(payload :: any, meta, state) :: on_message

  @callback handle_exception(Exception.t, state) :: on_message

  @type state :: GenQueue.state

  @type meta :: map

  @type on_callback :: GenQueue.on_callback

  @type on_message :: { on_message_action, state }
                    | { on_message_action, options :: Keyword.t, state }
                    | GenQueue.on_callback

  @type on_message_action :: :ack | :nack | :reject | :cancel

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Freddy.GenConsumer

      use Freddy.GenQueue, [queue: nil] ++ opts

      alias Freddy.Conn.{Chan, Queue}

      # Public functions

      @doc """
      Returns queue name which consumer is subscribed to.
      """
      @spec queue(GenServer.server) :: String.t
      def queue(consumer) do
        Connection.call(consumer, :queue, :infinity)
      end

      # GenQueue callbacks

      @doc false
      def handle_connect(state) do
        new_state =
          state
          |> declare_queue(queue_spec(state.opts))
          |> bind_queue()
          |> consume()

        {:noreply, new_state}
      end

      defoverridable [handle_connect: 1]

      # Overridable callbacks

      @doc false
      def queue_spec(opts) do
        name = Keyword.fetch!(opts, :queue)
        opts = Keyword.delete(opts, :queue)

        {name, opts}
      end

      defoverridable [queue_spec: 1]

      @doc false
      def handle_ready(_meta, state),
        do: {:noreply, state}

      defoverridable [handle_ready: 2]

      @doc false
      def handle_message(_payload, _meta, state),
        do: {:ack, state}

      defoverridable [handle_message: 3]

      @doc false
      def handle_exception(error, state),
        do: {:stop, {:error, error.message}, state}

      defoverridable [handle_exception: 2]

      # GenServer callbacks

      @doc false
      def handle_call(:queue, _from, state = %{queue: queue}),
        do: {:reply, queue, state}

      # Confirmation sent by the broker after registering this process as a consumer
      @doc false
      def handle_info({:basic_consume_ok, meta = %{consumer_tag: _consumer_tag}}, state) do
        handle_ready(meta, state)
      end

      # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
      @doc false
      def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
        {:stop, :shutdown, state}
      end

      # Confirmation sent by the broker to the consumer process after a Basic.cancel
      @doc false
      def handle_info({:basic_cancel_ok, %{consumer_tag: _consumer_tag}}, state) do
        {:stop, :normal, state}
      end

      # Handle new message delivery
      @doc false
      def handle_info({:basic_deliver, payload, meta = %{delivery_tag: tag}}, state) do
        try do
          payload
          |> handle_message(meta, state)
          |> handle_message_callback(tag)
        rescue error ->
          error
          |> handle_exception(state)
          |> handle_message_callback(tag)
        end
      end

      # GenConsumer private functions

      defp declare_queue(state = %{chan: chan}, {name, opts}) do
        {:ok, %{queue: queue}} = Queue.declare(chan, name, opts)
        %{state | queue: queue}
      end

      defp bind_queue(state = %{chan: chan, queue: queue, exchange: exchange}) do
        :ok = Queue.bind(chan, queue, exchange)
        state
      end

      defp consume(state = %{chan: chan, queue: queue}) do
        {:ok, _} = Chan.consume(chan, queue)
        state
      end

      @reply_actions [:ack, :nack, :reject, :cancel]

      defp handle_message_callback({action, state}, tag) when action in @reply_actions do
        handle_message_callback({action, [], state}, tag)
      end

      defp handle_message_callback({action, opts, state}, tag) when action in @reply_actions do
        apply(Chan, action, [state.chan, tag, opts])
        {:noreply, state}
      end

      defp handle_message_callback(ret, _tag) do
        ret
      end

      defp ack(state = %{chan: chan}, tag, opts),
        do: Chan.ack(chan, tag, opts)

      defp nack(state = %{chan: chan}, tag, opts),
        do: Chan.nack(chan, tag, opts)

      defp reject(state = %{chan: chan}, tag, opts),
        do: Chan.reject(chan, tag, opts)

      defp cancel(state = %{chan: chan}, tag, opts),
        do: Chan.cancel(chan, tag, opts)
    end
  end
end
