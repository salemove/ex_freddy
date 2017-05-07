defmodule Freddy.RPC.Client.State do
  @moduledoc false
  defstruct [:mod, :timeout, :routing_key, :waiting, :given]

  def new(mod, timeout, routing_key, given) do
    %__MODULE__{
      mod: mod,
      timeout: timeout,
      routing_key: routing_key,
      given: given,
      waiting: %{}
    }
  end

  def update(state, new_given),
    do: %{state | given: new_given}

  def push_waiting(%{waiting: waiting} = state, from, %{} = meta) do
    meta = Map.put(meta, :start_time, System.monotonic_time())
    new_waiting = Map.put(waiting, from, meta)
    %{state | waiting: new_waiting}
  end

  def pop_waiting(%{waiting: waiting} = state, from) do
    {meta, new_waiting} = Map.pop(waiting, from, %{})
    meta = Map.put(meta, :stop_time, System.monotonic_time())
    {meta, %{state | waiting: new_waiting}}
  end
end
