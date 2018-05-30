defmodule Freddy.Exchange do
  @moduledoc """
  Exchange configuration.

  # Fields

    * `:name` - Exchange name. If left empty, default exchange will be used.
    * `:type` - Exchange type. Can be `:direct`, `:topic`, `:fanout` or
      an arbitrary string, such as `"x-delayed-message"`. Default is `:direct`.
    * `:opts` - Exchange options. See below.

  ## Exchange options

    * `:durable` - If set, keeps the Exchange between restarts of the broker.
    * `:auto_delete` - If set, deletes the Exchange once all queues unbind from it.
    * `:passive` - If set, returns an error if the Exchange does not already exist.
    * `:internal` - If set, the exchange may not be used directly by publishers, but
      only when bound to other exchanges. Internal exchanges are used to construct
      wiring that is not visible to applications.
    * `:nowait` - If set, the server will not respond to the method and client
      will not wait for a reply. Default is `false`.
    * `:arguments` - A set of arguments for the declaration. The syntax and semantics
      of these arguments depends on the server implementation.

  See `AMQP.Exchange.declare/4` for more information.

  ## Example

    iex> %Freddy.Exchange{name: "freddy-topic", type: :topic, durable: true}
  """

  use Freddy.AMQP, name: "", type: :direct, opts: []

  @doc """
  Returns default exchange configuration. Such exchange implicitly exists in RabbitMQ
  and can't be declared by the clients.
  """
  @spec default() :: t
  def default do
    %__MODULE__{}
  end

  @doc false
  @spec declare(t, AMQP.Channel.t()) :: :ok | {:error, atom}
  def declare(%__MODULE__{name: ""}, _channel) do
    :ok
  end

  def declare(%__MODULE__{} = exchange, channel) do
    safe_amqp(on_error: {:error, :exchange_error}) do
      AMQP.Exchange.declare(channel, exchange.name, exchange.type, exchange.opts)
    end
  end

  @doc false
  @spec publish(t, AMQP.Channel.t(), String.t(), String.t(), Keyword.t()) :: :ok | {:error, atom}
  def publish(%__MODULE__{} = exchange, channel, message, routing_key, opts) do
    case AMQP.Basic.publish(channel, exchange.name, routing_key, message, opts) do
      :ok -> :ok
      reason -> {:error, reason}
    end
  end
end
