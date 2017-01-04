defmodule Freddy.RPC.Client.Middleware.JSON do
  use Freddy.RPC.Client.Middleware

  @default_engine Poison
  @content_type "application/json"

  def call(request, next, opts \\ []) do
    engine = Keyword.get(opts, :engine, @default_engine)

    request
    |> encode(engine)
    |> put_opt(:content_type, @content_type)
    |> run(next)
    |> decode(engine)
  end

  defp encode(request, engine) do
    process(request, :encode, engine)
  end

  defp decode(request = %{status: :ok}, engine) do
    process(request, :decode, engine)
  end

  defp decode(request, _engine) do
    request
  end

  defp process(request = %{payload: payload}, operation, engine) do
    case apply(engine, operation, [payload]) do
      {:ok, encoded} ->
        update_payload(request, encoded)

      error ->
        throw(error)
    end
  end
end
