defmodule Freddy.RPC.Client.State do
  defstruct conn: nil,
            conn_ref: nil,
            queue: nil,
            reply_queue: nil,
            producer: nil,
            consumer: nil,
            waiting: nil,
            status: nil

  alias __MODULE__
  alias Freddy.Conn
  alias Freddy.RPC.Client.{Consumer, Producer}

  def new(conn, queue),
    do: %State{conn: conn, queue: queue, waiting: %{}, status: :not_connected}

  def connect(state) do
    state
    |> monitor_connection()
    |> start_consumer()
  end

  def consumer_connected(state = %{consumer: consumer}) do
    new_state = %{state | reply_queue: Consumer.queue(consumer)}

    start_producer(new_state)
  end

  def producer_connected(state) do
    %{state | status: :connected}
  end

  def disconnect(state) do
    %{state | status: :not_connected}
    |> stop_producer()
    |> stop_consumer()
    |> reply_all({:error, :disconnected})
    |> demonitor_connection()
  end

  def reconnect(state) do
    state
    |> disconnect()
    |> connect()
  end

  # Client will die only if Freddy.Conn is dead
  def down?(state, ref),
    do: state.conn_ref == ref

  def request(state, client, payload, opts) do
    if connected?(state) do
      {:noreply, publish(state, client, payload, opts)}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  def reply(state = %{waiting: waiting}, correlation_id, response) do
    if from = Map.get(waiting, correlation_id) do
      Connection.reply(from, response)
      {:ok, %{state | waiting: Map.delete(waiting, correlation_id)}}
    else
      {:error, :not_found}
    end
  end

  def reply_all(state = %{waiting: waiting}, response) do
    Enum.each(waiting, fn {_, client} ->
      Connection.reply(client, response)
    end)

    %{state | waiting: %{}}
  end

  defp monitor_connection(state = %{conn: conn}) do
    %{state | conn_ref: Process.monitor(conn) }
  end

  defp demonitor_connection(state = %{conn_ref: conn_ref}) do
    if conn_ref,
      do: Process.demonitor(conn_ref)

    %{state | conn_ref: nil}
  end

  defp start_consumer(state = %{conn: conn}) do
    {:ok, consumer} = Consumer.start_link(conn, client: self())
    Consumer.notify_on_connect(consumer)

    %{state | consumer: consumer}
  end

  defp stop_consumer(state = %{consumer: consumer}) do
    if !is_nil(consumer) && Process.alive?(consumer),
      do: Consumer.stop(consumer)

    %{state | consumer: nil, reply_queue: nil}
  end

  defp start_producer(state = %{conn: conn}) do
    {:ok, producer} = Producer.start_link(conn, client: self())
    Producer.notify_on_connect(producer)

    %{state | producer: producer}
  end

  defp stop_producer(state = %{producer: producer}) do
    if !is_nil(producer) && Process.alive?(producer),
      do: Producer.stop(producer)

    %{state | producer: nil}
  end

  defp publish(state = %{producer: producer, queue: queue, waiting: waiting}, client, payload, opts) do
    correlation_id = Keyword.fetch!(opts, :correlation_id)
    Producer.produce(producer, queue, payload, opts)

    new_waiting = Map.put(waiting, correlation_id, client)

    %{state | waiting: new_waiting}
  end

  defp connected?(%{conn: conn, status: status}),
    do: status == :connected && Conn.status(conn) == :connected
end
