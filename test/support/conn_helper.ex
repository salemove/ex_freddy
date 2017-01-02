defmodule Freddy.ConnHelper do
  def open_connection(opts \\ []) do
    Freddy.Conn.start_link(Keyword.put(opts, :adapter, :sandbox))
  end
end
