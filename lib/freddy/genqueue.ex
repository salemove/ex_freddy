defmodule Freddy.GenQueue do
  @moduledoc """
  A behaviour module for implementing AMQP Producers/Consumers.
  """

  defmacro __using__(properties \\ []) do
    quote bind_quoted: [properties: properties], location: :keep do
      use Connection

      defmodule State do
        use Freddy.GenQueue.State, properties
      end

      alias __MODULE__.State, as: State

      @doc """
      Generic interface to start Producer/Consumer.
      """
      def start_link(conn, opts \\ []),
        do: Connection.start_link(__MODULE__, [conn, opts])

      def start(conn, opts \\ []),
        do: Connection.start(__MODULE__, [conn, opts])

      def stop(pid),
        do: Connection.call(pid, {:close, :normal})

      def status(pid),
        do: Connection.call(pid, :status)

      def notify_on_connect(pid, listener_pid \\ self()),
        do: Connection.cast(pid, {:notify_on_connect, listener_pid})

      def connected?(pid),
        do: status(pid) == :connected

      # GenQueue overridable callbacks

      def init_worker(state, _opts),
        do: state

      def handle_connect(state),
        do: {:noreply, state}

      # Will disconnect by default
      def handle_disconnect(reason, state),
        do: {:disconnect, reason, state}

      def terminate(_reason, state),
        do: State.disconnect(state)

      defoverridable [init_worker: 2,
        handle_connect: 1, handle_disconnect: 2, terminate: 2]

      # GenServer/Connection callbacks

      def init([conn, opts]) do
        state =
          State.new(conn, opts)
          |> init_worker(opts)

        {:connect, :init, state}
      end

      def connect(info, state) do
        new_state = State.connect(state, info)
        {:ok, new_state}
      end

      def disconnect(reason, state),
        do: {:stop, reason, state}

      def handle_call({:close, reason}, _from, state),
        do: {:disconnect, reason, :ok, state}

      def handle_call(:status, _from, state),
        do: {:reply, state.status, state}

      def handle_cast({:notify_on_connect, from}, state),
        do: {:noreply, State.notify_on_connect(state, from)}

      def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
        # Stop worker if Freddy.conn went down
        if State.down?(state, ref) do
          {:disconnect, :disconnected, state}
        else
          handle_disconnect(reason, state)
        end
      end

      def handle_info({:CHANNEL, {:ok, chan}, _conn}, state) do
        new_state = State.connected(state, chan)
        handle_connect(new_state)
      end

      def handle_info({:CHANNEL, {:error, reason}, _conn}, state) do
        {:disconnect, reason, state}
      end
    end
  end
end
