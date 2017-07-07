defmodule Freddy.RPC.Client.State do
  @moduledoc false
  defstruct [:mod, :timeout, :waiting, :given]

  def new(mod, timeout, given) do
    %__MODULE__{
      mod: mod,
      timeout: timeout,
      given: given,
      waiting: %{}
    }
  end

  def update(state, new_given),
    do: %{state | given: new_given}

  def push_waiting(%{waiting: waiting} = state, %{id: id} = req) do
    new_waiting = Map.put(waiting, id, req)
    %{state | waiting: new_waiting}
  end

  def pop_waiting(%{waiting: waiting} = state, id) do
    if Map.has_key?(waiting, id) do
      {req, new_waiting} = Map.pop(waiting, id)
      new_state = %{state | waiting: new_waiting}
      {:ok, req, new_state}
    else
      {:error, :not_found}
    end
  end
end
