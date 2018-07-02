defmodule Freddy.Adapter.Sandbox.Channel do
  @moduledoc false

  use GenServer

  alias Freddy.Adapter.Sandbox.Connection

  def open(connection) do
    case Connection.get_on_open_channel(connection) do
      :ok -> GenServer.start_link(__MODULE__, connection)
      other -> other
    end
  end

  def monitor(channel) do
    Process.monitor(channel)
  end

  def close(channel) do
    GenServer.stop(channel)
  end

  def register(channel, event, args) do
    GenServer.call(channel, {:register, event, args})
  end

  @impl true
  def init(connection) do
    {:ok, connection}
  end

  @impl true
  def handle_call({:register, event, args}, _from, connection) do
    {:reply, Connection.register(connection, event, args), connection}
  end
end
