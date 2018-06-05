defmodule Freddy.Core.Channel do
  @moduledoc false

  @type t :: %__MODULE__{
          adapter: module,
          chan: term
        }

  defstruct [:adapter, :chan]

  def open(adapter, connection) do
    case adapter.open_channel(connection) do
      {:ok, chan} ->
        {:ok, %__MODULE__{adapter: adapter, chan: chan}}

      error ->
        error
    end
  end

  def monitor(%{adapter: adapter, chan: chan}) do
    adapter.monitor_channel(chan)
  end

  def close(%{adapter: adapter, chan: chan}) do
    adapter.close_channel(chan)
  end

  def register_return_handler(%{adapter: adapter, chan: chan}, pid) do
    adapter.register_return_handler(chan, pid)
  end
end
