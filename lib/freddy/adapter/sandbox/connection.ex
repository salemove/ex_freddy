defmodule Freddy.Adapter.Sandbox.Connection do
  @moduledoc false

  use GenServer

  def open(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  def link(pid) do
    Process.link(pid)
  end

  def close(pid) do
    GenServer.stop(pid)
  end

  def register(connection, event, args) do
    GenServer.call(connection, {:register, event, args})
  end

  def history(connection, type) do
    GenServer.call(connection, {:history, type})
  end

  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call({:register, event, args}, _from, history) do
    {:reply, :ok, [{event, args} | history]}
  end

  def handle_call({:history, :all}, _from, history) do
    {:reply, Enum.reverse(history), history}
  end

  def handle_call({:history, type}, _from, history) do
    matching_events =
      Enum.reduce(history, [], fn
        {^type, _} = event, acc -> [event | acc]
        _, acc -> acc
      end)

    {:reply, matching_events, history}
  end
end
