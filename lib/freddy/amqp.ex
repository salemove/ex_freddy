defmodule Freddy.AMQP do
  @moduledoc false
  # A declarable AMQP entity + a macro for safer execution of some operations

  @callback new(struct | Keyword.t()) :: struct
  @callback declare(struct, AMQP.Channel.t()) :: :ok | {:ok, term} | {:error, atom}
  @optional_callbacks declare: 2

  defmacro __using__(fields) do
    quote do
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__)

      @type t :: %__MODULE__{}
      defstruct unquote(fields)

      def new(%__MODULE__{} = exchange) do
        exchange
      end

      def new(config) when is_list(config) do
        struct!(__MODULE__, config)
      end
    end
  end

  defmacro safe_amqp([on_error: on_error], do: expr) do
    quote do
      try do
        unquote(expr)
      rescue
        MatchError ->
          # amqp 0.x throws MatchError when server responds with non-OK
          unquote(on_error)
      catch
        :exit, {:noproc, _} ->
          {:error, :closed}

        _, _ ->
          {:error, :closed}
      end
    end
  end
end
