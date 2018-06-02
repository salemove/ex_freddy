defmodule Freddy.AMQP.Queue do
  @moduledoc false

  alias Freddy.AMQP.Channel

  import AMQP.Core
  import AMQP.Utils

  def declare(channel, queue, options) do
    queue_declare =
      queue_declare(
        queue: queue,
        durable: Keyword.get(options, :durable, false),
        auto_delete: Keyword.get(options, :auto_delete, false),
        exclusive: Keyword.get(options, :exclusive, false),
        passive: Keyword.get(options, :passive, false),
        nowait: Keyword.get(options, :nowait, false),
        arguments: Keyword.get(options, :arguments, []) |> to_type_tuple()
      )

    case Channel.call(channel, queue_declare) do
      queue_declare_ok(queue: queue) -> {:ok, queue}
      error -> error
    end
  end

  def bind(channel, queue, exchange, options) do
    queue_bind =
      queue_bind(
        queue: queue,
        exchange: exchange,
        routing_key: Keyword.get(options, :routing_key, ""),
        nowait: Keyword.get(options, :no_wait, false),
        arguments: Keyword.get(options, :arguments, []) |> to_type_tuple()
      )

    case Channel.call(channel, queue_bind) do
      queue_bind_ok() -> :ok
      error -> error
    end
  end
end
