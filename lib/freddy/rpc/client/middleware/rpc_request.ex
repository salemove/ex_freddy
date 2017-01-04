defmodule Freddy.RPC.Client.Middleware.RPCRequest do
  use Freddy.RPC.Client.Middleware

  def call(request = %{client: client}, next, _opts \\ []) do
    request
    |> put_opt(:correlation_id, generate_correlation_id())
    |> put_opt(:reply_to, Client.reply_queue(client))
    |> put_opt(:type, "request")
    |> put_opt(:mandatory, true)
    |> run(next)
    |> handle_response()
  end

  defp handle_response(%{status: :ok, payload: payload}) do
    {:ok, payload}
  end

  defp handle_response(%{status: :error, error: reason}) do
    {:error, reason}
  end

  defp generate_correlation_id,
    do: :erlang.unique_integer() |> to_string() |> Base.encode64()
end
