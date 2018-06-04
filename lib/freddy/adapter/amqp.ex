defmodule Freddy.Adapter.AMQP do
  @moduledoc false

  @behaviour Freddy.Adapter

  alias Freddy.Adapter.AMQP.{Basic, Channel, Connection, Exchange, Queue}

  # Connection management

  @impl true
  defdelegate open_connection(options), to: Connection, as: :open

  @impl true
  defdelegate link_connection(connection), to: Connection, as: :link

  @impl true
  defdelegate close_connection(connection), to: Connection, as: :close

  # Channel management

  @impl true
  defdelegate open_channel(connection), to: Channel, as: :open

  @impl true
  defdelegate monitor_channel(pid), to: Channel, as: :monitor

  @impl true
  defdelegate close_channel(pid), to: Channel, as: :close

  @impl true
  defdelegate register_return_handler(channel, pid), to: Channel

  # Exchanges

  @impl true
  defdelegate declare_exchange(channel, name, type, options), to: Exchange, as: :declare

  @impl true
  defdelegate bind_exchange(channel, destination, source, options), to: Exchange, as: :bind

  # Queues

  @impl true
  defdelegate declare_queue(channel, queue, options), to: Queue, as: :declare

  @impl true
  defdelegate bind_queue(channel, queue, exchange, options), to: Queue, as: :bind

  # Basic

  @impl true
  defdelegate publish(channel, exchange, routing_key, payload, options), to: Basic

  @impl true
  defdelegate consume(channel, queue, consumer_pid, options), to: Basic

  @impl true
  defdelegate qos(channel, options), to: Basic

  @impl true
  defdelegate ack(channel, delivery_tag, options), to: Basic

  @impl true
  defdelegate nack(channel, delivery_tag, options), to: Basic

  @impl true
  defdelegate reject(channel, delivery_tag, options), to: Basic

  @impl true
  defdelegate handle_message(message), to: Basic
end
