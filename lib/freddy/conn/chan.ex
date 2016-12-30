defmodule Freddy.Conn.Chan do
  defstruct [:given]

  alias AMQP.Basic
  alias AMQP.Channel
  alias AMQP.Queue

  alias Freddy.Conn.Exchange

  def new(given),
    do: %__MODULE__{given: given}

  def open(conn),
    do: Freddy.Conn.open_channel(conn)

  def request(conn),
    do: Freddy.Conn.request_channel(conn)

  def alive?(%{given: given}),
    do: given && given.pid && Process.alive?(given.pid)

  def close(chan = %{given: given}) do
    if alive?(chan), do: Channel.close(given)
  end

  def monitor(%{given: given}),
    do: Process.monitor(given.pid)

  def link(%{given: given}),
    do: Process.link(given.pid)

  def unlink(%{given: given}),
    do: Process.unlink(given.pid)

  def declare_queue(%{given: given}, name, opts \\ []),
    do: Queue.declare(given, name, opts)

  def consume(%{given: given}, queue, consumer_pid \\ nil, opts \\ []),
    do: Basic.consume(given, queue, consumer_pid, opts)

  def publish(%{given: given}, %Exchange{name: exchange}, routing_key, payload, opts \\ []),
    do: Basic.publish(given, exchange, routing_key, payload, opts)

  def register_return_handler(%{given: %{pid: pid}}, handler_pid),
    do: :amqp_channel.register_return_handler(pid, handler_pid)

  def unregister_return_handler(chan = %{given: given}) do
    if alive?(chan),
      do: :amqp_channel.unregister_return_handler(given.pid)
  end

  def ack(%{given: given}, tag),
    do: Basic.ack(given, tag)

  def nack(%{given: given}, tag),
    do: Basic.nack(given, tag)

  def reject(%{given: given}, tag),
    do: Basic.reject(given, tag)

  def cancel(%{given: given}, tag),
    do: Basic.cancel(given, tag)
end
