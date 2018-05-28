defmodule Freddy.Exchange do
  @moduledoc """
  Exchange configuration.

  # Options

    * `:durable`: If set, keeps the Exchange between restarts of the broker;
    * `:auto_delete`: If set, deletes the Exchange once all queues unbind from it;
    * `:passive`: If set, returns an error if the Exchange does not already exist;
    * `:internal:` If set, the exchange may not be used directly by publishers, but
      only when bound to other exchanges. Internal exchanges are used to construct
      wiring that is not visible to applications.

  See `AMQP.Exchange.declare/4` for more information.
  """

  @type t :: %__MODULE__{}

  defstruct name: "", type: :direct, opts: []

  def new(%__MODULE__{} = exchange) do
    exchange
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  def default do
    %__MODULE__{}
  end

  @spec declare(t, AMQP.Channel.t()) :: :ok | {:error, atom}
  def declare(%__MODULE__{name: ""}, _channel) do
    :ok
  end

  def declare(%__MODULE__{} = exchange, channel) do
    try do
      AMQP.Exchange.declare(channel, exchange.name, exchange.type, exchange.opts)
    rescue
      MatchError ->
        # amqp 0.x throws MatchError when server responds with non-OK
        {:error, :exchange_error}
    end
  end

  @spec publish(t, AMQP.Channel.t(), String.t(), String.t(), Keyword.t()) :: :ok | {:error, atom}
  def publish(%__MODULE__{} = exchange, channel, message, routing_key, opts) do
    case AMQP.Basic.publish(channel, exchange.name, routing_key, message, opts) do
      :ok -> :ok
      reason -> {:error, reason}
    end
  end
end
