defmodule Freddy.Conn.Adapter.Sandbox.Connection do
  use GenServer
  alias __MODULE__
  alias Freddy.Conn.Adapter.Sandbox.{Channel, Broker, History}

  defstruct [:pid]

  def open(opts) do
    with {:ok, broker} = Broker.start(opts),
         {:ok, conn} = start(broker, opts),
         do: {:ok, %Connection{pid: conn}}
  end

  def open_channel(%{pid: pid}) do
    GenServer.call(pid, :open_channel)
  end

  def close(%{pid: pid}, reason \\ :normal),
    do: GenServer.stop(pid, reason)

  def consume(%{pid: pid}, queue, consumer, opts) do
    GenServer.call(pid, {:consume, queue, consumer, opts})
  end

  def publish(%{pid: pid}, chan, queue, payload, opts) do
    GenServer.cast(pid, {:publish, chan, queue, payload, opts})
  end

  def messages(%{pid: pid}) do
    GenServer.call(pid, :messages)
  end

  def history(%{pid: pid}) do
    GenServer.call(pid, :history)
  end

  def register(%{pid: pid}, event, payload) do
    register(pid, event, payload)
  end

  def register(conn, event, payload) do
    GenServer.cast(conn, {:register, event, payload})
  end

  def kill_broker(%{pid: pid}, reason \\ :kill) do
    GenServer.cast(pid, {:kill_broker, reason})
  end

  # Private functions

  def start(broker, opts) do
    GenServer.start(__MODULE__, [broker, opts])
  end

  def init([broker, opts]) do
    Process.flag(:trap_exit, true)
    Process.monitor(broker)

    history =
      case Keyword.get(opts, :history) do
        pid when is_pid(pid) -> pid

        true ->
          {:ok, history} = History.start_link()
          history

        _ -> nil
      end

    do_register(history, :connect, self())

    {:ok, {broker, history}}
  end

  def handle_call(:open_channel, _from, state) do
    case Channel.open(%Connection{pid: self()}) do
      {:ok, chan} ->
        Process.monitor(chan.pid)
        {:reply, {:ok, chan}, state}

      anything ->
        {:reply, anything, state}
    end
  end

  def handle_call({:consume, queue, pid, _opts}, _from, state = {broker, _history}) do
    {:reply, Broker.consume(broker, queue, pid), state}
  end

  def handle_call(:messages, _from, state = {broker, _history}) do
    {:reply, Broker.messages(broker), state}
  end

  def handle_call(:history, _from, state = {_broker, history}) do
    if history do
      {:reply, History.events(history), state}
    else
      {:reply, nil, state}
    end
  end

  def handle_cast({:publish, chan, queue, payload, opts}, state = {broker, _history}) do
    Broker.publish(broker, chan, queue, payload, opts)
    {:noreply, state}
  end

  def handle_cast({:register, event, payload}, state = {_broker, history}) do
    do_register(history, event, payload)
    {:noreply, state}
  end

  def handle_cast({:kill_broker, reason}, state = {broker, _history}) do
    Broker.stop(broker, reason)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, process, _reason}, state = {process, _history}) do
    {:stop, :socket_closed_unexpectedly, state}
  end

  def handle_info({:DOWN, _ref, :process, _from, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _from, reason}, state) do
    {:stop, reason, state}
  end

  def terminate(reason, {_broker, history}) do
    do_register(history, :connection_terminate, reason)
  end

  defp do_register(_history = nil, _event, _payload),
    do: :ok

  defp do_register(history, event, payload),
    do: History.register(history, {event, payload})
end
