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

  def history(connection, type, flush?) do
    GenServer.call(connection, {:history, type, flush?})
  end

  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call({:register, event, args}, _from, history) do
    {:reply, :ok, [{event, args} | history]}
  end

  def handle_call({:history, :all, flush?}, _from, history) do
    {:reply, Enum.reverse(history), flush(history, flush?)}
  end

  def handle_call({:history, types, flush?}, _from, history) do
    matching_events =
      Enum.reduce(history, [], fn {type, _} = event, acc ->
        if type in List.wrap(types) do
          [event | acc]
        else
          acc
        end
      end)

    {:reply, matching_events, flush(history, flush?)}
  end

  defp flush(history, flag) do
    if flag do
      []
    else
      history
    end
  end
end
