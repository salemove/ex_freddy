defmodule Freddy.Bind do
  @moduledoc """
  Queue-Exchange or Exchange-Exchange binding configiration

  ## Options

    * `:routing_key` - Specifies the routing key for the binding. The routing
      key is used for routing messages depending on the exchange configuration.
      Not all exchanges use a routing key - refer to the specific exchange
      documentation. Default is `"#"`.
    * `:nowait` - If set, the server will not respond to the method and client
      will not wait for a reply. Default is `false`.
    * `:arguments` - A set of arguments for the binding. The syntax and semantics
      of these arguments depends on the exchange class.

  ## Example

      iex> %Freddy.Bind{routing_key: "a_key"}
  """

  use Freddy.AMQP, routing_key: "#", nowait: false, arguments: []

  alias Freddy.Queue
  alias Freddy.Exchange

  @doc false
  # Binds given `queue_or_exchange` to the given `exchange`.
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

  @doc false
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
