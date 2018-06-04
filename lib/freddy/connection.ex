defmodule Freddy.Connection do
  @moduledoc """
  Stable AMQP connection.
  """

  alias Freddy.Utils.MultikeyMap
  alias Freddy.Adapter
  alias Freddy.Channel

  @type connection :: GenServer.server()

  # Hard coded for now, can make configurable later
  @reconnect_interval 1000

  use Connection

  @doc """
  Start a new AMQP connection. See `AMQP.Connection.open/1` for supported
  connection options.
  """
  @spec start_link(Keyword.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(connection_opts \\ [], gen_server_opts \\ []) do
    Connection.start_link(__MODULE__, connection_opts, gen_server_opts)
  end

  @doc """
  Closes an AMQP connection. This will cause process to reconnect.
  """
  @spec close(connection, timeout) :: :ok | {:error, reason :: term}
  def close(connection, timeout \\ 5000) do
    Connection.call(connection, {:close, timeout})
  end

  @doc """
  Stops the connection process
  """
  def stop(connection) do
    GenServer.stop(connection)
  end

  @doc """
  Opens a new AMQP channel
  """
  @spec open_channel(connection) :: {:ok, Freddy.Channel.t()} | {:error, reason :: term}
  def open_channel(connection) do
    Connection.call(connection, :open_channel)
  end

  @doc """
  Returns underlying connection PID
  """
  @spec get_connection(connection) :: {:ok, Freddy.Adapter.connection()} | {:error, :closed}
  def get_connection(connection) do
    Connection.call(connection, :get)
  end

  @doc false
  @spec child_spec(term) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  # Connection callbacks

  import Record

  defrecordp :state,
    adapter: nil,
    opts: nil,
    connection: nil,
    channels: MultikeyMap.new()

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {adapter, opts} = Keyword.pop(opts, :adapter, :amqp)
    {:connect, :init, state(opts: opts, adapter: Adapter.get(adapter))}
  end

  @impl true
  def connect(_info, state(adapter: adapter, opts: opts) = state) do
    case adapter.open_connection(opts) do
      {:ok, connection} ->
        adapter.link_connection(connection)
        {:ok, state(state, connection: connection)}

      _error ->
        {:backoff, @reconnect_interval, state}
    end
  end

  @impl true
  def disconnect(_info, state) do
    {:connect, :reconnect, state(state, connection: nil)}
  end

  @impl true
  def handle_call(_, _, state(connection: nil) = state) do
    {:reply, {:error, :closed}, state}
  end

  def handle_call(:get, _from, state(connection: connection) = state) do
    {:reply, {:ok, connection}, state}
  end

  def handle_call(
        :open_channel,
        {from, _ref},
        state(adapter: adapter, connection: connection, channels: channels) = state
      ) do
    try do
      case Channel.open(adapter, connection) do
        {:ok, chan} ->
          monitor_ref = Process.monitor(from)
          channel_ref = Channel.monitor(chan)
          channels = MultikeyMap.put(channels, [monitor_ref, channel_ref], chan)

          {:reply, {:ok, chan}, state(state, channels: channels)}

        {:error, _reason} = reply ->
          {:reply, reply, state}
      end
    catch
      :exit, {:noproc, _} ->
        {:reply, {:error, :closed}, state}

      _, _ ->
        {:reply, {:error, :closed}, state}
    end
  end

  def handle_call({:close, timeout}, _from, state(adapter: adapter, connection: connection) = state) do
    {:disconnect, :close, close_connection(adapter, connection, timeout), state}
  end

  @impl true
  def handle_info(
        {:EXIT, connection, {:shutdown, :normal}},
        state(connection: connection) = state
      ) do
    {:noreply, state(state, connection: nil)}
  end

  def handle_info({:EXIT, connection, reason}, state(connection: connection) = state) do
    {:disconnect, {:error, reason}, state}
  end

  def handle_info({:EXIT, _process, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info({:DOWN, ref, _, _pid, _reason}, state) do
    {:noreply, close_channel(ref, state)}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state(adapter: adapter, connection: connection)) do
    if connection do
      adapter.close_connection(connection)
    end
  end

  defp close_channel(ref, state(channels: channels) = state) do
    case MultikeyMap.pop(channels, ref) do
      {nil, ^channels} ->
        state

      {channel, new_channels} ->
        Channel.close(channel)
        state(state, channels: new_channels)
    end
  end

  defp close_connection(adapter, connection, timeout) do
    try do
      adapter.close_connection(connection)

      receive do
        {:EXIT, ^connection, _reason} -> :ok
      after
        timeout ->
          Process.exit(connection, :kill)

          receive do
            {:EXIT, ^connection, _reason} -> :ok
          end
      end
    catch
      :exit, {:noproc, _} -> {:error, :closed}
    end
  end
end
