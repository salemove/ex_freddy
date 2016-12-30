defmodule Freddy.GenConsumer do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      use Freddy.GenQueue, [queue: nil] ++ opts

      alias Freddy.Conn.{Chan, Queue}

      # Public functions

      def queue(consumer) do
        Connection.call(consumer, :queue, :infinity)
      end

      # GenQueue callbacks

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

      def queue_spec(opts) do
        name = Keyword.fetch!(opts, :queue)
        opts = Keyword.delete(opts, :queue)

        {name, opts}
      end

      defoverridable [queue_spec: 1]

      def handle_ready(state, _meta),
        do: {:noreply, state}

      defoverridable [handle_ready: 2]

      def handle_message(_payload, _meta, state),
        do: {:ack, state}

      defoverridable [handle_message: 3]

      def handle_exception(error, state),
        do: {:stop, {:error, error.message}, state}

      defoverridable [handle_exception: 2]

      # GenServer callbacks

      def handle_call(:queue, _from, state = %{queue: queue}),
        do: {:reply, queue, state}

      # Confirmation sent by the broker after registering this process as a consumer
      def handle_info({:basic_consume_ok, meta = %{consumer_tag: _consumer_tag}}, state) do
        handle_ready(state, meta)
      end

      # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
      def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
        {:stop, :shutdown, state}
      end

      # Confirmation sent by the broker to the consumer process after a Basic.cancel
      def handle_info({:basic_cancel_ok, %{consumer_tag: _consumer_tag}}, state) do
        {:stop, :normal, state}
      end

      # Handle new message delivery
      def handle_info({:basic_deliver, payload, meta = %{delivery_tag: tag}}, state) do
        try do
          {action, new_state} = handle_message(payload, meta, state)

          case action do
            :ack    -> ack(new_state, tag)
            :nack   -> nack(new_state, tag)
            :reject -> reject(new_state, tag)
            :cancel -> cancel(new_state, tag)
            _ -> raise ArgumentError, "Bad return from handle_message/3: #{inspect action}"
          end

          {:noreply, new_state}
        rescue error ->
          reject(state, tag)
          handle_exception(error, state)
        end
      end

      # GenConsumer private functions

      defp declare_queue(state = %{chan: chan}, {name, opts}) do
        {:ok, %{queue: queue}} = Queue.declare(chan, name, opts)
        %{state | queue: queue}
      end

      defp bind_queue(state = %{exchange: %{name: ""}}),
        do: state # don't bind to default exchange

      defp bind_queue(state = %{chan: chan, queue: queue, exchange: exchange}) do
        :ok = Queue.bind(chan, queue, exchange)
        state
      end

      defp consume(state = %{chan: chan, queue: queue}) do
        {:ok, _} = Chan.consume(chan, queue)
        state
      end

      defp ack(state = %{chan: chan}, tag),
        do: Chan.ack(chan, tag)

      defp nack(state = %{chan: chan}, tag),
        do: Chan.nack(chan, tag)

      defp reject(state = %{chan: chan}, tag),
        do: Chan.reject(chan, tag)

      defp cancel(state = %{chan: chan}, tag),
        do: Chan.cancel(chan, tag)
    end
  end
end
