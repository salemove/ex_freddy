defmodule Freddy.Conn.State.Waiting do
  alias __MODULE__

  defstruct [:clients]

  def new,
    do: %Waiting{clients: []}

  def push(waiting = %Waiting{clients: clients}, client),
    do: %{waiting | clients: [client | clients]}

  def pop_all(waiting = %Waiting{clients: clients}),
    do: {clients, %{waiting | clients: []}}
end
