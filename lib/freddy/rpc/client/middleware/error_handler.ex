defmodule Freddy.RPC.Client.Middleware.ErrorHandler do
  use Freddy.RPC.Client.Middleware

  def call(request, next, _opts \\ []) do
    try do
      run(request, next)
    catch
      {:error, reason} ->
        %{request | status: :error, error: reason}

      :exit, {reason, _} ->
        %{request | status: :error, error: reason}
    end
  end
end
