defmodule Freddy.Core.Exchange do
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

  ## Example

      iex> %Freddy.Core.Exchange{name: "freddy-topic", type: :topic, durable: true}
  """

  @type t :: %__MODULE__{
          name: String.t(),
          type: atom | String.t(),
          opts: options
        }

  @type options :: [
          durable: boolean,
          auto_delete: boolean,
          passive: boolean,
          internal: boolean,
          nowait: boolean,
          arguments: Keyword.t()
        ]

  defstruct name: "", type: :direct, opts: []

  @doc """
  Create exchange configuration from keyword list or `Freddy.Core.Exchange` structure.
  """
  @spec new(t | Keyword.t()) :: t
  def new(%__MODULE__{} = exchange) do
    exchange
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  @doc """
  Returns default exchange configuration. Such exchange implicitly exists in RabbitMQ
  and can't be declared by the clients.
  """
  @spec default() :: t
  def default do
    %__MODULE__{}
  end

  @doc false
  @spec declare(t, Freddy.Core.Channel.t()) :: :ok | {:error, atom}
  def declare(%__MODULE__{name: ""}, _channel) do
    :ok
  end

  def declare(%__MODULE__{} = exchange, %{adapter: adapter, chan: chan}) do
    adapter.declare_exchange(chan, exchange.name, exchange.type, exchange.opts)
  end

  @doc false
  @spec publish(t, Freddy.Core.Channel.t(), String.t(), String.t(), Keyword.t()) ::
          :ok | {:error, atom}
  def publish(%__MODULE__{} = exchange, %{adapter: adapter, chan: chan}, message, routing_key, opts) do
    Freddy.Tracer.with_send_span(exchange, routing_key, fn tracing_headers ->
      opts =
        if opts[:disable_trace_propagation] do
          opts
        else
          new_headers = Keyword.merge(opts[:headers] || [], tracing_headers)
          Keyword.put(opts, :headers, new_headers)
        end

      adapter.publish(chan, exchange.name, routing_key, message, opts)
    end)
  end
end
