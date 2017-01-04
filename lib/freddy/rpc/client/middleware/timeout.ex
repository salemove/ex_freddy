defmodule Freddy.RPC.Client.Middleware.Timeout do
  @moduledoc """
  This middleware sets timeout option for request.

  # Usage

  defmodule MyCient do
    use Freddy.RPC.Client,
        connection: MyClient.Connection,
        queue: "queue"

    use Middleware.Timeout, default: 5000
  end
  """

  use Freddy.RPC.Client.Middleware

  @default_timeout 3000

  def call(request = %{opts: opts}, next, middleware_opts \\ []) do
    default = Keyword.get(middleware_opts, :default, @default_timeout)
    timeout = Keyword.get(opts, :timeout, default)

    request
    |> put_env(:client_timeout, timeout)
    |> run_with_timeout(next, timeout)
  end

  defp run_with_timeout(request, next, :infinity) do
    run(request, next)
  end

  defp run_with_timeout(request, next, timeout) do
    request
    # expiration value has to be a string, otherwise
    # rabbit_framing_amqp_0_9_1:encode_properties/1 (rabbit_common package) fails
    |> put_opt(:expiration, to_string(timeout))
    |> run(next)
  end
end
