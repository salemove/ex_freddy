defmodule Freddy.Bind do
  @moduledoc """
  Queue-Exchange or Exchange-Exchange binding configiration
  """

  @type t :: %__MODULE__{}

  defstruct routing_key: nil, nowait: false, arguments: []

  alias Freddy.Queue
  alias Freddy.Exchange

  def new(%__MODULE__{} = bind) do
    bind
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  @doc """
  Binds given `queue_or_exchange` to the given `exchange`.
  """
  @spec declare(t, Exchange.t(), Exchange.t() | Queue.t(), AMQP.Channel.t()) :: :ok | {:error, atom}
  def declare(bind, exchange, queue_or_exchange, channel)

  def declare(_bind, _queue, %Exchange{name: ""}, _channel) do
    :ok
  end

  def declare(bind, %Exchange{} = exchange, %Queue{} = queue, channel) do
    try do
      AMQP.Queue.bind(channel, queue.name, exchange.name, as_opts(bind))
    rescue
      MatchError ->
        # amqp 0.x throws MatchError when server responds with non-OK
        {:error, :bind_error}
    end
  end

  def declare(bind, %Exchange{} = exchage, %Exchange{} = source, channel) do
    try do
      AMQP.Exchange.bind(channel, exchage.name, source.name, as_opts(bind))
    rescue
      MatchError ->
        {:error, :bind_error}
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
