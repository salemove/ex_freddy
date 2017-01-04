defmodule Freddy.RPC.Client.BuilderTest do
  use ExUnit.Case

  defmodule TestBuilder do
    use Freddy.RPC.Client.Builder

    plug JsonMiddleware, engine: JSON
    plug LoggingMiddleware
    plug :local_function
    plug :local_function_with_opts, some_opt: :value
  end

  test "builds middleware stack" do
    assert TestBuilder.__middleware__() == [
      {JsonMiddleware, :call, [[engine: JSON]]},
      {LoggingMiddleware, :call, [[]]},
      {TestBuilder, :local_function, [[]]},
      {TestBuilder, :local_function_with_opts, [[some_opt: :value]]}
    ]
  end
end
