defmodule Freddy.GenQueue.State do
  alias Freddy.Conn.{Chan, Exchange}
  alias Freddy.Conn.State.Waiting

  defmacro __using__(properties) do
    quote bind_quoted: [properties: properties] do
      @base_properties [
        opts: nil, # `opts` argument passed to `GenQueue.start_link/2`
        conn: nil,
        conn_ref: nil,
        chan: nil,
        chan_ref: nil,
        exchange: nil,
        status: nil,
        waiting: nil
      ]

      defstruct @base_properties ++ properties

      alias __MODULE__

      def new(conn, opts) do
        exchange =
          opts
          |> Keyword.get(:exchange, [])
          |> Exchange.new()

        %State{conn: conn, opts: opts, exchange: exchange, status: :not_connected, waiting: Waiting.new()}
      end

      def connect(state),
        do: connect(state, :init)

      def connect(state, _info = :reconnect) do
        state
        |> disconnect()
        |> connect()
      end

      def connect(state = %{conn: conn}, _info) do
        state
        |> monitor_connection()
        |> request_channel()
      end

      def connected(state, chan) do
        state
        |> set_channel(chan)
        |> declare_exchange()
        |> notify_waiting({:ok, :connected})
      end

      def disconnect(state = %{conn_ref: conn_ref, chan_ref: chan_ref}) do
        state
        |> demonitor_connection()
        |> close_channel()
        |> notify_waiting({:error, :disconnected})
      end

      def notify_on_connect(state = %{status: :connected}, client) do
        notify(client, {:ok, :connected})
        state
      end

      def notify_on_connect(state = %{waiting: waiting}, client) do
        %{state | waiting: Waiting.push(waiting, client)}
      end

      def down?(state, ref),
        do: state.conn_ref == ref

      # Private functions

      defp monitor_connection(state = %{conn: conn}),
        do: %{state | conn_ref: Process.monitor(conn)}

      defp demonitor_connection(state = %{conn_ref: ref}) do
        safe_demonitor(ref)
        %{state | conn_ref: nil}
      end

      defp open_channel(state = %{conn: conn}) do
        {:ok, chan} = Chan.open(conn)

        %{state | chan: chan, chan_ref: Chan.monitor(chan)}
      end

      defp request_channel(state = %{conn: conn}) do
        Chan.request(conn)
        %{state | status: :connecting}
      end

      defp set_channel(state, chan),
        do: %{state | chan: chan, chan_ref: Chan.monitor(chan), status: :connected}

      defp close_channel(state = %{chan: chan, chan_ref: ref}) do
        if chan, do: Chan.close(chan)

        safe_demonitor(ref)

        %{state | chan: nil, chan_ref: nil, status: :not_connected}
      end

      defp declare_exchange(state = %{chan: chan, exchange: exchange}) do
        Exchange.declare(exchange, chan)
        state
      end

      defp safe_demonitor(ref) when is_reference(ref),
        do: Process.demonitor(ref)

      defp safe_demonitor(_),
        do: :ok

      defp notify_waiting(state = %{waiting: waiting}, result) do
        {clients, new_waiting} = Waiting.pop_all(waiting)

        Enum.each(clients, fn client ->
          notify(client, result)
        end)

        %{state | waiting: new_waiting}
      end

      defp notify(client, result),
        do: send(client, {:GENQUEUE_CONNECTION, result, self()})
    end
  end
end
