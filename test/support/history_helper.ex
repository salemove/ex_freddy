defmodule Freddy.HistoryHelper do
  alias Freddy.Conn.Adapter.Sandbox.History

  def spawn_history do
    History.start_link()
  end

  def flush_history(history) do
    events = History.events(history)
    Enum.each(events, fn event -> send(self(), event) end)
  end
end
