defmodule Freddy.Bind do
  @moduledoc """
  Queue-Exchange or Exchange-Exchange binding configiration
  """

  use Freddy.AMQP, routing_key: nil, nowait: false, arguments: []

  alias Freddy.Queue
  alias Freddy.Exchange

  @doc """
  Binds given `queue_or_exchange` to the given `exchange`.
  """
  @spec declare(t, Exchange.t(), Exchange.t() | Queue.t(), AMQP.Channel.t()) :: :ok | {:error, atom}
  def declare(bind, exchange, queue_or_exchange, channel)

  def declare(_bind, _queue, %Exchange{name: ""}, _channel) do
    :ok
  end

  def declare(bind, %Exchange{} = exchange, %Queue{} = queue, channel) do
    safe_amqp(on_error: {:error, :bind_error}) do
      AMQP.Queue.bind(channel, queue.name, exchange.name, as_opts(bind))
    end
  end

  def declare(bind, %Exchange{} = exchage, %Exchange{} = source, channel) do
    safe_amqp(on_error: {:error, :bind_error}) do
      AMQP.Exchange.bind(channel, exchage.name, source.name, as_opts(bind))
    end
  end

  @spec declare_multiple([t], Exchange.t(), Exchange.t() | Queue.t(), AMQP.Channel.t()) ::
          :ok | {:error, atom}
  def declare_multiple(binds, exchange, queue_or_exchange, channel) do
    Enum.reduce_while(binds, :ok, fn bind, _acc ->
      case declare(bind, exchange, queue_or_exchange, channel) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp as_opts(%__MODULE__{} = bind) do
    bind
    |> Map.from_struct()
    |> Keyword.new()
  end
end
