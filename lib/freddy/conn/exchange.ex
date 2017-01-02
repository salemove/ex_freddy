defmodule Freddy.Conn.Exchange do
  @moduledoc """
  Echange configuration, extracted from `opts`
  """
  defstruct [:name, :type, :opts, :default?]

  alias __MODULE__
  alias Freddy.Conn.Chan

  @default_exchange ""

  def new(options) do
    name = Keyword.get(options, :name, @default_exchange)
    type = Keyword.get(options, :type, :direct)

    opts =
      options
      |> Keyword.delete(:name)
      |> Keyword.delete(:type)

    %Exchange{name: name, type: type, opts: opts, default?: name == @default_exchange}
  end

  def declare(exchange = %Exchange{default?: true}, _chan) do
    exchange
  end

  def declare(exchange = %Exchange{name: name, type: type, opts: opts}, %Chan{adapter: adapter, given: chan}) do
    adapter.declare_exchange(chan, name, type, opts)
    exchange
  end
end
