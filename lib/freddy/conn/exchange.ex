defmodule Freddy.Conn.Exchange do
  @moduledoc """
  Echange configuration, extracted from `opts`
  """
  defstruct [:name, :type, :opts]

  alias __MODULE__
  alias Freddy.Conn.Chan

  def new(options) do
    name = Keyword.get(options, :name, "")
    type = Keyword.get(options, :type, :direct)

    opts =
      options
      |> Keyword.delete(:name)
      |> Keyword.delete(:type)

    %Exchange{name: name, type: type, opts: opts}
  end

  def declare(exchange = %Exchange{name: name, type: type, opts: opts}, %Chan{given: chan}) do
    if name != "" do
      AMQP.Exchange.declare(chan, name, type, opts)
    end

    exchange
  end
end
