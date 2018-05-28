defmodule Freddy.Conn do
  @moduledoc false

  @doc false
  def start_link(config \\ [], opts \\ []) do
    IO.warn(
      "#{__MODULE__}.start_link/2 is deprecated, use Freddy.Connection.start_link/2 instead",
      Macro.Env.stacktrace(__ENV__)
    )

    Freddy.Connection.start_link(config, opts)
  end
end
