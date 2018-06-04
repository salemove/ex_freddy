defmodule Freddy.Core.Bind do
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

      iex> %Freddy.Core.Bind{routing_key: "a_key"}
  """

  alias Freddy.Core.Queue
  alias Freddy.Core.Exchange
  alias Freddy.Core.Channel

  @type t :: %__MODULE__{
          routing_key: String.t(),
          nowait: boolean,
          arguments: Keyword.t()
        }

  defstruct channel: nil, routing_key: "#", nowait: false, arguments: []

  @doc """
  Create binding configuration from keyword list or `Freddy.Core.Bind` structure.
  """
  @spec new(t | Keyword.t()) :: t
  def new(%__MODULE__{} = bind) do
    bind
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  @doc false
  # Binds given `queue_or_exchange` to the given `exchange`.
  @spec declare(t, Exchange.t(), Exchange.t() | Queue.t(), Channel.t()) :: :ok | {:error, atom}
  def declare(bind, exchange, queue_or_exchange, channel)

  def declare(_bind, _queue, %Exchange{name: ""}, _channel) do
    :ok
  end

  def declare(bind, %Exchange{} = exchange, %Queue{} = queue, %{adapter: adapter, chan: chan}) do
    adapter.bind_queue(chan, queue.name, exchange.name, as_opts(bind))
  end

  def declare(bind, %Exchange{} = exchange, %Exchange{} = source, %{adapter: adapter, chan: chan}) do
    adapter.bind_exchange(chan, exchange.name, source.name, as_opts(bind))
  end

  @doc false
  @spec declare_multiple([t], Exchange.t(), Exchange.t() | Queue.t(), Channel.t()) ::
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
