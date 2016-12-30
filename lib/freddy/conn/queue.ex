defmodule Freddy.Conn.Queue do
  alias AMQP.Queue

  alias Freddy.Conn.{Chan, Exchange}

  def declare(%Chan{given: given}, queue, opts \\ []),
    do: Queue.declare(given, queue, opts)

  def bind(%Chan{given: given}, queue, %Exchange{name: exchange}, opts \\ []),
    do: Queue.bind(given, queue, exchange, opts)

  def unbind(%Chan{given: given}, queue, %Exchange{name: exchange}, opts \\ []),
    do: Queue.unbind(given, queue, exchange, opts)

  def delete(%Chan{given: given}, queue, opts \\ []),
    do: Queue.delete(given, queue, opts)
end
