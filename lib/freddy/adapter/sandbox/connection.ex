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

  def set_on_open_channel(connection, response) do
    GenServer.cast(connection, {:set_on_open_channel, response})
  end

  def get_on_open_channel(connection) do
    GenServer.call(connection, :get_on_open_channel)
  end

  def register(connection, event, args) do
    GenServer.call(connection, {:register, event, args})
  end

  def history(connection, type, flush?) do
    GenServer.call(connection, {:history, type, flush?})
  end

  def add_listener(connection, dest) do
    GenServer.call(connection, {:add_listener, dest})
  end

  def remove_listener(connection, dest) do
    GenServer.call(connection, {:remove_listener, dest})
  end

  @impl true
  def init(_) do
    {:ok, %{history: [], listeners: [], on_open_channel: :ok}}
  end

  @impl true
  def handle_call(
        {:register, event, args},
        _from,
        %{history: history, listeners: listeners} = state
      ) do
    new_history = [{event, args} | history]

    Enum.each(listeners, fn dest -> send(dest, {event, args}) end)

    {:reply, :ok, put_in(state[:history], new_history)}
  end

  def handle_call({:history, :all, flush?}, _from, %{history: history} = state) do
    new_history = flush(history, flush?)
    {:reply, Enum.reverse(history), put_in(state[:history], new_history)}
  end

  def handle_call({:history, types, flush?}, _from, %{history: history} = state) do
    matching_events =
      Enum.reduce(history, [], fn {type, _} = event, acc ->
        if type in List.wrap(types) do
          [event | acc]
        else
          acc
        end
      end)

    new_history = flush(history, flush?)
    {:reply, matching_events, put_in(state[:history], new_history)}
  end

  def handle_call({:add_listener, dest}, _from, %{listeners: listeners} = state) do
    new_listeners = [dest | listeners]
    {:reply, :ok, put_in(state[:listeners], new_listeners)}
  end

  def handle_call({:remove_listener, dest}, _from, %{listeners: listeners} = state) do
    new_listeners = List.delete(listeners, dest)
    {:reply, :ok, put_in(state[:listeners], new_listeners)}
  end

  def handle_call(:get_on_open_channel, _from, %{on_open_channel: resp} = state) do
    {:reply, resp, state}
  end

  @impl true
  def handle_cast({:set_on_open_channel, resp}, state) do
    {:noreply, put_in(state[:on_open_channel], resp)}
  end

  defp flush(history, flag) do
    if flag do
      []
    else
      history
    end
  end
end
