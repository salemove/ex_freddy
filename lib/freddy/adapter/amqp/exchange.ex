defmodule Freddy.Adapter.AMQP.Exchange do
  @moduledoc false

  import Freddy.Adapter.AMQP.Core
  alias Freddy.Adapter.AMQP.Channel

  def declare(channel, exchange, type, options) do
    exchange_declare =
      exchange_declare(
        exchange: exchange,
        type: to_string(type),
        passive: Keyword.get(options, :passive, false),
        auto_delete: Keyword.get(options, :auto_delete, false),
        internal: Keyword.get(options, :internal, false),
        nowait: Keyword.get(options, :nowait, false),
        arguments: Keyword.get(options, :arguments, []) |> to_type_tuple()
      )

    case Channel.call(channel, exchange_declare) do
      exchange_declare_ok() -> :ok
      error -> error
    end
  end

  def bind(channel, destination, source, options) do
    exchange_bind =
      exchange_bind(
        destination: destination,
        source: source,
        routing_key: Keyword.get(options, :routing_key, ""),
        nowait: Keyword.get(options, :nowait, false),
        arguments: Keyword.get(options, :arguments, []) |> to_type_tuple()
      )

    case Channel.call(channel, exchange_bind) do
      exchange_bind_ok() -> :ok
      error -> error
    end
  end
end
