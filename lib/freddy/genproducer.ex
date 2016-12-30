defmodule Freddy.GenProducer do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      use Freddy.GenQueue, opts

      import AMQP.Core
      import Record

      alias Freddy.Conn.Chan

      defmodule Message do
        defstruct [:destination, :payload, :options]
      end

      # Public functions

      def produce(producer, destination, payload, options \\ []),
        do: Connection.call(producer, {:produce, destination, payload, options})

      # GenProducer overridable callbacks

      def handle_message(message, state),
        do: {:ok, message, state}

      defoverridable [handle_message: 2]

      def handle_no_route(_payload, _properties, state),
        do: {:noreply, state}

      defoverridable [handle_no_route: 3]

      # GenQueue callbacks

      def handle_connect(state = %{chan: chan}) do
        Chan.register_return_handler(chan, self())
        {:noreply, state}
      end

      def terminate(reason, state = %{chan: chan}) do
        Chan.unregister_return_handler(chan)

        super(reason, state)
      end

      defoverridable [handle_connect: 1]

      # GenServer callbacks

      def handle_call({:produce, destination, payload, options}, _from, state = %{chan: chan, exchange: exchange}) do
        message = %Message{destination: destination, payload: payload, options: options}

        case handle_message(message, state) do
          {:ok, new_message, new_state} ->
            :ok = Chan.publish(chan, exchange, new_message.destination, new_message.payload, new_message.options)
            {:reply, new_message, new_state}

          other ->
            other
        end
      end

      Record.defrecordp :amqp_msg, [props: p_basic(), payload: ""]

      def handle_info(
        { basic_return(reply_text: "NO_ROUTE"), amqp_msg(props: p_basic() = properties, payload: payload) },
        state
      ) do
        handle_no_route(payload, p_basic(properties), state)
      end
    end
  end
end
