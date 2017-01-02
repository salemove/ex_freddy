defmodule Freddy.Conn.Adapter.Sandbox.Channel do
  use GenServer
  import AMQP.Core

  require Record
  Record.defrecordp :amqp_msg, [props: p_basic(), payload: ""]

  alias __MODULE__
  alias Freddy.Conn.Adapter.Sandbox.Connection

  defstruct [:conn, :pid]

  defmodule State do
    defstruct [:conn, :ref, :return_handler]
  end

  def open(conn) do
    {:ok, pid} = GenServer.start(__MODULE__, conn)
    {:ok, %Channel{conn: conn, pid: pid}}
  end

  def close(%Channel{pid: pid}) do
    GenServer.stop(pid)
  end

  def register_return_handler(%Channel{pid: pid}, handler_pid) do
    GenServer.cast(pid, {:register_return_handler, handler_pid})
  end

  def unregister_return_handler(%Channel{pid: pid}) do
    GenServer.cast(pid, :unregister_return_handler)
  end

  def return_message(%Channel{pid: pid}, payload, properties) do
    GenServer.cast(pid, {:return_message, payload, properties})
  end

  def init(conn) do
    ref = Process.monitor(conn.pid)
    state = %State{conn: conn, ref: ref, return_handler: nil}

    {:ok, state}
  end

  def handle_cast({:register_return_handler, pid}, state) do
    {:noreply, %{state | return_handler: pid}}
  end

  def handle_cast(:unregister_return_handler, state) do
    {:noreply, %{state | return_handler: nil}}
  end

  def handle_cast({:return_message, _, _}, state = %{return_handler: nil}) do
    {:noreply, state}
  end

  def handle_cast({:return_message, payload, properties}, state = %{return_handler: return_handler}) do
    props =
      p_basic(
        content_type: properties[:content_type],
        content_encoding: properties[:content_encoding],
        headers: properties[:headers],
        delivery_mode: properties[:delivery_mode],
        priority: properties[:priority],
        correlation_id: properties[:correlation_id],
        reply_to: properties[:reply_to],
        expiration: properties[:expiration],
        message_id: properties[:message_id],
        timestamp: properties[:timestamp],
        type: properties[:type],
        user_id: properties[:user_id],
        app_id: properties[:app_id],
        cluster_id: properties[:cluster_id]
      )

    message = { basic_return(reply_text: "NO_ROUTE"), amqp_msg(props: props, payload: payload) }
    send(return_handler, message)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state = %{ref: ref}) do
    Process.demonitor(ref)
    {:stop, reason, %{state | ref: nil}}
  end

  def terminate(:normal, _state),
    do: :ok

  def terminate(reason, %{conn: conn}),
    do: Connection.close(conn, reason)
end
