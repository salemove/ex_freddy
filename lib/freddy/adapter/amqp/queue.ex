defmodule Freddy.Adapter.AMQP.Queue do
  @moduledoc false

  import Freddy.Adapter.AMQP.Core
  alias Freddy.Adapter.AMQP.Channel

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

  def unbind(channel, queue, exchange, options) do
    queue_unbind =
      queue_unbind(
        queue: queue,
        exchange: exchange,
        routing_key: Keyword.get(options, :routing_key, ""),
        arguments: Keyword.get(options, :arguments, []) |> to_type_tuple()
      )

    case Channel.call(channel, queue_unbind) do
      queue_unbind_ok() -> :ok
      error -> error
    end
  end

  def delete(channel, queue, options) do
    queue_delete =
      queue_delete(
        queue: queue,
        if_unused: Keyword.get(options, :if_unused, false),
        if_empty: Keyword.get(options, :if_empty, false),
        nowait: Keyword.get(options, :no_wait, false)
      )

    case Channel.call(channel, queue_delete) do
      queue_delete_ok(message_count: message_count) -> {:ok, %{message_count: message_count}}
      error -> error
    end
  end
end
