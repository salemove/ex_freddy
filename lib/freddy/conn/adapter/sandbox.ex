defmodule Freddy.Conn.Adapter.Sandbox do
  alias Freddy.Conn.Adapter.Sandbox.{Connection, Channel}

  # Connection

  def open_connection(opts \\ []),
    do: Connection.open(opts)

  def monitor_connection(conn = %Connection{pid: pid}) do
    register(conn, :monitor_connection, {:from, self()})
    Process.monitor(pid)
  end

  def close_connection(conn = %Connection{}) do
    register(conn, :close_connection, {})
    Connection.close(conn)
  end

  # Backdoor functions (for testing)

  def history(conn = %Connection{}) do
    Connection.history(conn)
  end

  def disconnect(conn, reason \\ :simulated_crash) do
    Connection.kill_broker(conn, reason)
  end

  # Channel

  def open_channel(conn = %Connection{}) do
    register(conn, :open_channel, {})
    Connection.open_channel(conn)
  end

  def close_channel(chan = %Channel{}) do
    register(chan, :close_channel, chan)
    Channel.close(chan)
  end

  def monitor_channel(chan = %Channel{pid: pid}) do
    register(chan, :monitor_channel, {chan, :from, self()})
    Process.monitor(pid)
  end

  def link_channel(chan = %Channel{pid: pid}) do
    register(chan, :link_channel, {chan, :from, self()})
    Process.link(pid)
  end

  def unlink_channel(chan = %Channel{pid: pid}) do
    register(chan, :unlink_channel, {chan, :from, self()})
    Process.unlink(pid)
  end

  def register_return_handler(chan = %Channel{}, handler_pid) do
    register(chan, :register_return_handler, {chan, handler_pid})
    Channel.register_return_handler(chan, handler_pid)
  end

  def unregister_return_handler(chan = %Channel{}) do
    register(chan, :unregister_return_handler, chan)
    Channel.unregister_return_handler(chan)
  end

  # Queue
  def declare_queue(chan, name, opts \\ [])

  def declare_queue(chan, "", opts) do
    name = generate_queue_name()
    register(chan, :declare_queue, {:auto, name, opts})
    {:ok, %{queue: name, message_count: 0, consumer_count: 0}}
  end

  def declare_queue(chan, name, opts) do
    register(chan, :declare_queue, {:name, name, opts})
    {:ok, %{queue: name, message_count: 0, consumer_count: 0}}
  end

  def bind_queue(chan, queue, exchange, opts \\ []) do
    register(chan, :bind_queue, {queue, exchange, opts})
    :ok
  end

  def unbind_queue(chan, queue, exchange, opts \\ []) do
    register(chan, :unbind_queue, {queue, exchange, opts})
    :ok
  end

  def delete_queue(chan, queue, opts \\ []) do
    register(chan, :delete_queue, {queue, opts})
    :ok
  end

  # Exchange

  def declare_exchange(chan, name, type, opts \\ []) do
    register(chan, :declare_exchange, {name, type, opts})
    :ok
  end

  # Produce/Consume

  def consume(chan = %Channel{conn: conn}, queue, consumer_pid \\ nil, opts \\ []) do
    pid = consumer_pid || self()
    register(chan, :consume, {queue, pid, opts})
    Connection.consume(conn, queue, pid, opts)
  end

  def publish(chan = %Channel{conn: conn}, exchange, routing_key, payload, opts \\ []) do
    register(chan, :publish, {exchange, routing_key, payload, opts})
    Connection.publish(conn, chan, routing_key, payload, opts)
  end

  def ack(chan, tag, opts \\ []) do
    register(chan, :ack, {tag, opts})
    :ok
  end

  def nack(chan, tag, opts \\ []) do
    register(chan, :nack, {tag, opts})
    :ok
  end

  def reject(chan, tag, opts \\ []) do
    register(chan, :reject, {tag, opts})
    :ok
  end

  def cancel(chan, tag, opts \\ []) do
    register(chan, :cancel, {tag, opts})
    :ok
  end

  defp register(%Channel{conn: conn}, event, payload),
    do: register(conn, event, payload)

  defp register(conn = %Connection{}, event, payload),
    do: Connection.register(conn, event, payload)

  defp generate_queue_name,
    do: :erlang.unique_integer() |> to_string() |> Base.encode64()
end
