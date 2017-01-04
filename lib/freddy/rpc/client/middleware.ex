defmodule Freddy.RPC.Client.Middleware do
  alias Freddy.RPC.Client

  defmacro __using__(_) do
    quote do
      alias Freddy.RPC.Client
      alias Client.Request

      import Client.Middleware
      import Client.Request
    end
  end

  def run(req, stack)

  def run(req, []), do: req

  def run(req, [{:fun, f}]), do: apply(f, [req])
  def run(req, [{mod, fun}]), do: apply(mod, fun, [req])
  def run(req, [{mod, fun, args}]), do: apply(mod, fun, [req, args])

  def run(req, [{:fun, f} | rest]), do: apply(f, [req, rest])
  def run(req, [{mod, fun} | rest]), do: apply(mod, fun, [req, rest])
  def run(req, [{mod, fun, args} | rest]), do: apply(mod, fun, [req, rest | args])
end
