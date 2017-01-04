defmodule Freddy.RPC.Client.Builder do
  @moduledoc false

  defmacro __using__(_opts) do
    quote location: :keep do
      Module.register_attribute(__MODULE__, :__middleware__, accumulate: true)

      import Freddy.RPC.Client.Builder, only: [plug: 1, plug: 2]
      @before_compile Freddy.RPC.Client.Builder
    end
  end

  defmacro plug(middleware, opts \\ []) do
    quote do: @__middleware__ {unquote(middleware), unquote(opts)}
  end

  defmacro __before_compile__(env) do
    middleware =
      env.module
      |> Module.get_attribute(:__middleware__)
      |> prepare_middleware_stack(env.module)
      |> Enum.reverse()
      |> Macro.escape()

    quote do
      def __middleware__, do: unquote(middleware)
    end
  end

  defp prepare_middleware_stack([], _mod), do: []
  defp prepare_middleware_stack([middleware | rest], mod) do
    [prepare_middleware(mod, middleware) | prepare_middleware_stack(rest, mod)]
  end

  defp prepare_middleware(mod, {middleware, opts}) do
    case Atom.to_string(middleware) do
      "Elixir." <> _ -> {middleware, :call, [opts]}
      _ -> {mod, middleware, [opts]}
    end
  end
end
