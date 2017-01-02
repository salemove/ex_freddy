defmodule Freddy.Conn.Adapter do
  alias Freddy.Conn.Adapter.{AMQP, Sandbox}

  @default AMQP

  @doc """
  Returns Adapter module by its short name
  """
  @spec new(adapter :: Atom.t) :: Atom.t
  def new(adapter_name)

  def new(:amqp),
    do: AMQP

  def new(:sandbox),
    do: Sandbox

  def new(_),
    do: @default
end
