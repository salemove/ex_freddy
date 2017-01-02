defmodule Freddy.Conn.Adapter.AMQP do
  alias AMQP.{Basic,
              Channel,
              Connection,
              Exchange,
              Queue}

  # Connection

  def open_connection(opts \\ []),
    do: Connection.open(opts)

  def monitor_connection(%Connection{pid: pid}),
    do: Process.monitor(pid)

  def close_connection(conn = %Connection{}),
    do: Connection.close(conn)

  # Backdoor functions

  def history(_),
    do: []

  def disconnect(_conn, _reason \\ nil) do
    :ok
  end

  # Channel

  def open_channel(conn = %Connection{}),
    do: Channel.open(conn)

  def close_channel(chan = %Channel{}),
    do: Channel.close(chan)

  def monitor_channel(%Channel{pid: pid}),
    do: Process.monitor(pid)

  def link_channel(%Channel{pid: pid}),
    do: Process.link(pid)

  def unlink_channel(%Channel{pid: pid}),
    do: Process.unlink(pid)

  def register_return_handler(%Channel{pid: pid}, handler_pid),
    do: :amqp_channel.register_return_handler(pid, handler_pid)

  def unregister_return_handler(%Channel{pid: pid}),
    do: :amqp_channel.unregister_return_handler(pid)

  # Queue

  def declare_queue(chan = %Channel{}, name, opts \\ []),
    do: Queue.declare(chan, name, opts)

  def bind_queue(chan = %Channel{}, queue, exchange, opts \\ []),
    do: Queue.bind(chan, queue, exchange, opts)

  def unbind_queue(chan, queue, exchange, opts \\ []),
    do: Queue.unbind(chan, queue, exchange, opts)

  def delete_queue(chan, queue, opts \\ []),
    do: Queue.delete(chan, queue, opts)

  # Exchange

  def declare_exchange(chan = %Channel{}, name, type, opts \\ []),
    do: Exchange.declare(chan, name, type, opts)

  # Produce/Consume

  def consume(chan = %Channel{}, queue, consumer_pid \\ nil, opts \\ []),
    do: Basic.consume(chan, queue, consumer_pid, opts)

  def publish(chan = %Channel{}, exchange, routing_key, payload, opts \\ []),
    do: Basic.publish(chan, exchange, routing_key, payload, opts)

  def ack(chan = %Channel{}, tag, opts \\ []),
    do: Basic.ack(chan, tag, opts)

  def nack(chan = %Channel{}, tag, opts \\ []),
    do: Basic.nack(chan, tag, opts)

  def reject(chan = %Channel{}, tag, opts \\ []),
    do: Basic.reject(chan, tag, opts)

  def cancel(chan = %Channel{}, tag, opts \\ []),
    do: Basic.cancel(chan, tag, opts)
end
