defmodule Freddy.Conn.State do
  alias __MODULE__
  alias __MODULE__.Waiting

  alias Freddy.Conn.Chan
  alias Freddy.Conn.Adapter

  defstruct config: nil,
            adapter: nil,
            waiting: nil,
            given_conn: nil,
            monitor: nil,
            backoff: nil,
            status: nil

  @default_backoff [1, 2, 3, 4, 5, 7, 10, 12, 15, 18]

  def new(config) do
    adapter = Adapter.new(Keyword.get(config, :adapter))
    waiting = Waiting.new()

    %State{ config: config, adapter: adapter, waiting: waiting, status: :not_connected }
  end

  def connect(state = %{adapter: adapter, config: config}) do
    case adapter.open_connection(config) do
      {:ok, conn}      -> connected(state, conn)
      {:error, reason} -> retry(state, reason)
    end
  end

  def disconnect(state = %{waiting: waiting}) do
    {clients, new_waiting} = Waiting.pop_all(waiting)
    reject_waiting(clients, {:error, :disconnected})

    disconnected = close_connection(state)

    {:ok, %{disconnected | waiting: new_waiting}}
  end

  def open_channel(state, client) do
    state
    |> do_open_channel()
    |> handle_open_channel(state, client)
  end

  def request_channel(state, client) do
    state
    |> do_open_channel()
    |> handle_request_channel(state, client)
  end

  def given_conn(%{given_conn: conn}),
    do: conn

  def status(%{status: status}),
    do: status

  def down?(state, monitor),
    do: state.monitor == monitor

  # Private interface

  defp retry(state = %{backoff: nil, config: config}, reason) do
    [initial | rest] = backoff_intervals(config)
    {:retry, reason, :timer.seconds(initial), %{state | backoff: rest, status: :reconnecting}}
  end

  defp retry(state = %{backoff: [interval | rest]}, reason),
    do: {:retry, reason, :timer.seconds(interval), %{state | backoff: rest, status: :reconnecting}}

  defp retry(state = %{backoff: []}, reason),
    do: {:exhausted, reason, %{state | status: :not_connected}}

  defp do_open_channel(%{adapter: adapter, given_conn: conn, status: :connected}) do
    with {:ok, chan} <- adapter.open_channel(conn),
     do: {:ok, Chan.new(adapter, chan)}
  end

  defp do_open_channel(_),
    do: :not_connected

  defp handle_open_channel({:ok, chan}, _state, _client),
    do: {:ok, chan}

  defp handle_open_channel(:not_connected, state = %{waiting: waiting}, client),
    do: {:wait, %{state | waiting: Waiting.push(waiting, {:sync, client})}}

  defp handle_open_channel(error = {:error, _reason}, _state, _client),
    do: error

  defp handle_request_channel(:not_connected, state = %{waiting: waiting}, client),
    do: %{state | waiting: Waiting.push(waiting, {:async, client})}

  defp handle_request_channel(result, state, client) do
    reply({:async, client}, result)
    state
  end

  defp connected(state = %{adapter: adapter}, conn) do
    monitor = adapter.monitor_connection(conn)
    {clients, waiting} = Waiting.pop_all(state.waiting)

    new_state = %{
      state |
      given_conn: conn,
      status: :connected,
      monitor: monitor,
      waiting: waiting,
      backoff: nil
    }

    reply_waiting(new_state, clients)

    {:ok, new_state}
  end

  defp close_connection(state = %{adapter: adapter, given_conn: conn, monitor: ref}) do
    if is_reference(ref) do
      Process.demonitor(ref)
    end

    if conn && conn.pid && Process.alive?(conn.pid) do
      adapter.close_connection(conn)
    end

    %{state | given_conn: nil, monitor: nil, status: :not_connected}
  end

  defp reject_waiting(clients, result) do
    Enum.each(clients, fn client ->
      reply(client, result)
    end)
  end

  defp reply_waiting(state, clients) do
    Enum.each(clients, fn client ->
      reply(client, do_open_channel(state))
    end)
  end

  defp reply({:async, client}, response) do
    send(client, {:CHANNEL, response, self()})
  end

  defp reply({:sync, client}, response) do
    Connection.reply(client, response)
  end

  def backoff_intervals(config) do
    Keyword.get(config, :backoff, @default_backoff)
  end
end
