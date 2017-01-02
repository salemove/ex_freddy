defmodule Freddy.Conn.Adapter.Sandbox.History do
  def start_link do
    Agent.start_link(fn -> [] end)
  end

  def register(history, event = {_type, _payload}) do
    Agent.update(history, fn events -> [event | events] end)
  end

  def events(history) do
    Agent.get(history, &Enum.reverse/1)
  end
end
