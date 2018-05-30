defmodule Freddy.Utils.SafeAMQP do
  @moduledoc false
  # A macro for safer execution of some operations

  @recoverable_error_codes [311, 320]

  defmacro safe_amqp([on_error: on_error], do: expr) do
    quote do
      try do
        unquote(expr)
      rescue
        MatchError ->
          # amqp 0.x throws MatchError when server responds with non-OK
          unquote(on_error)
      catch
        # recoverable
        :exit, {{:shutdown, {:server_initiated_close, code, _}}, _}
        when code in unquote(@recoverable_error_codes) ->
          {:error, :closed}

        # unrecoverable
        :exit, {{:shutdown, {:server_initiated_close, _, _}}, _} ->
          unquote(on_error)

        :exit, _ ->
          {:error, :closed}
      end
    end
  end
end
