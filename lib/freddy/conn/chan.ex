defmodule Freddy.Conn.Chan do
  defstruct [:adapter, :given]

  alias __MODULE__

  alias Freddy.Conn.Exchange

  def new(adapter, given),
    do: %Chan{adapter: adapter, given: given}

  def open(conn),
    do: Freddy.Conn.open_channel(conn)

  def request(conn),
    do: Freddy.Conn.request_channel(conn)

  def alive?(%{given: given}),
    do: given && given.pid && Process.alive?(given.pid)

  def close(chan = %{adapter: adapter, given: given}) do
    if alive?(chan), do: adapter.close_channel(given)
  end

  def monitor(%{adapter: adapter, given: given}),
    do: adapter.monitor_channel(given)

  def link(%{adapter: adapter, given: given}),
    do: adapter.link_channel(given)

  def unlink(%{adapter: adapter, given: given}),
    do: adapter.unlink_channel(given)

  def declare_queue(%{adapter: adapter, given: given}, name, opts \\ []),
    do: adapter.declare_queue(given, name, opts)

  def consume(%{adapter: adapter, given: given}, queue, consumer_pid \\ nil, opts \\ []),
    do: adapter.consume(given, queue, consumer_pid, opts)

  def publish(%{adapter: adapter, given: given}, %Exchange{name: exchange}, routing_key, payload, opts \\ []),
    do: adapter.publish(given, exchange, routing_key, payload, opts)

  def register_return_handler(%{adapter: adapter, given: given}, handler_pid),
    do: adapter.register_return_handler(given, handler_pid)

  def unregister_return_handler(chan = %{adapter: adapter, given: given}) do
    if alive?(chan),
      do: adapter.unregister_return_handler(given)
  end

  def ack(%{adapter: adapter, given: given}, tag, opts \\ []),
    do: adapter.ack(given, tag, opts)

  def nack(%{adapter: adapter, given: given}, tag, opts \\ []),
    do: adapter.nack(given, tag, opts)

  def reject(%{adapter: adapter, given: given}, tag, opts \\ []),
    do: adapter.reject(given, tag, opts)

  def cancel(%{adapter: adapter, given: given}, tag, opts \\ []),
    do: adapter.cancel(given, tag, opts)
end
