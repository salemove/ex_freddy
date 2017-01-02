defmodule Freddy.Conn.Queue do
  alias Freddy.Conn.{Chan, Exchange}

  def declare(%Chan{adapter: adapter, given: given}, queue, opts \\ []),
    do: adapter.declare_queue(given, queue, opts)

  def bind(chan, queue, exchange, opts \\ [])

  def bind(_chan, _queue, %Exchange{default?: true}, _opts),
    do: :ok

  def bind(%Chan{adapter: adapter, given: given}, queue, %Exchange{name: exchange}, opts),
    do: adapter.bind_queue(given, queue, exchange, opts)

  def unbind(%Chan{adapter: adapter, given: given}, queue, %Exchange{name: exchange}, opts \\ []),
    do: adapter.unbind_queue(given, queue, exchange, opts)

  def delete(%Chan{adapter: adapter, given: given}, queue, opts \\ []),
    do: adapter.delete_queue(given, queue, opts)
end
