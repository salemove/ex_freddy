defmodule Freddy.RPC.Client.Middleware.Logging do
  use Freddy.RPC.Client.Middleware
  require Logger

  def call(request, next, _opts \\ []) do
    request
    |> start()
    |> measure(next)
    |> log()
  end

  defp start(request = %{payload: payload, opts: opts}) do
    request
    |> put_env(:request_payload, payload)
    |> put_env(:request_opts, opts)
  end

  defp measure(request, next) do
    start = System.monotonic_time()

    request
    |> run(next)
    |> put_env(:elapsed, time_diff(start))
  end

  defp log(response = %{status: :ok, queue: queue, opts: opts, env: %{elapsed: elapsed}}) do
    Logger.info("Response from #{queue}: OK, correlation_id #{opts[:correlation_id]} (#{elapsed} ms)")
    response
  end

  defp log(response = %{status: :error, queue: queue, opts: opts, error: reason, env: %{elapsed: elapsed}}) do
    Logger.warn("Response from #{queue}: ERROR #{inspect reason}, correlation_id #{opts[:correlation_id]} (#{elapsed} ms)")
    response
  end

  defp time_diff(start),
    do: System.convert_time_unit(System.monotonic_time() - start, :native, :milli_seconds)
end
