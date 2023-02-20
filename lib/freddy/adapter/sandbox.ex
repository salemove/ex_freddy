defmodule Freddy.Adapter.Sandbox do
  @moduledoc """
  Special no-op Freddy adapter designed to be used in automated
  tests instead of real AMQP connection.

  ## Example

      iex> alias Freddy.{Connection, Core.Exchange, Adapter.Sandbox}
      iex> {:ok, conn} = Connection.start_link(adapter: :sandbox)
      iex> {:ok, channel} = Connection.open_channel(conn)
      iex> :ok = Exchange.declare(%Exchange{name: "test"}, channel)
      iex> {:ok, pid} = Connection.get_connection(conn)
      iex> Sandbox.history(pid)
      [
        link_connection: [#PID<0.226.0>],
        open_channel: [#PID<0.226.0>],
        monitor_channel: [#PID<0.228.0>],
        declare_exchange: [#PID<0.228.0>, "test", :direct, []]
      ]
  """

  @behaviour Freddy.Adapter

  alias Freddy.Adapter.Sandbox.{Connection, Channel}

  import Channel, only: [register: 3]

  @doc """
  Get history of events from connection. Events can be filtered by type,
  for example, if one wants to get only history of messages, published
  over given connection, he should call `history(connection, :publish)`.
  Filter by multiple event types is supported.

  Passing `true` as a third argument will erase entire history after
  returning it.
  """
  def history(connection, events \\ :all, flush? \\ false) do
    Connection.history(connection, events, flush?)
  end

  @doc """
  Sends a message to the process specified by `dest` whenever an
  event occurs.

  The messages will be tuples `{event, args}` where `event` is an atom
  that corresponds to a callback in the `Freddy.Adapter` module. `args` is
  a list of arguments passed to the callback.

  `dest` may be either a PID or a locally registered name (atom).

  ## Example

      iex> alias Freddy.{Connection, Core.Exchange, Adapter.Sandbox}
      iex> {:ok, conn} = Connection.start_link(adapter: :sandbox)
      iex> {:ok, pid} = Connection.get_connection(conn)
      iex> :ok = Sandbox.add_listener(pid, self())
      iex> {:ok, channel} = Connection.open_channel(conn)
      iex> :ok = Exchange.declare(%Exchange{name: "test"}, channel)
      iex> flush()
      {:open_channel, [#PID<0.226.0>]}
      {:monitor_channel, [#PID<0.228.0>]}
      {:declare_exchange, [#PID<0.228.0>, "test", :direct, []]}

  """
  def add_listener(connection, dest) do
    Connection.add_listener(connection, dest)
  end

  @doc """
  Removes a listener previously registered with `add_listener/2`.
  """
  def remove_listener(connection, dest) do
    Connection.remove_listener(connection, dest)
  end

  @doc """
  Sets a response for `open_channel/1` function. If set to `:ok`, the function
  will return a tuple `{:ok, channel_pid}` (default behaviour).
  """
  def on_open_channel(connection, response) do
    Connection.set_on_open_channel(connection, response)
  end

  @impl true
  defdelegate open_connection(opts), to: Connection, as: :open

  @impl true
  def link_connection(connection) do
    Connection.register(connection, :link_connection, [connection])
    Connection.link(connection)
    :ok
  end

  @impl true
  def close_connection(connection) do
    Connection.register(connection, :close_connection, [connection])
    Connection.close(connection)
  end

  @impl true
  def open_channel(connection) do
    Connection.register(connection, :open_channel, [connection])
    Channel.open(connection)
  end

  @impl true
  def monitor_channel(channel) do
    register(channel, :monitor_channel, [channel])
    Channel.monitor(channel)
  end

  @impl true
  def close_channel(channel) do
    register(channel, :close_channel, [channel])
    Channel.close(channel)
  end

  @impl true
  def register_return_handler(channel, pid) do
    register(channel, :register_return_handler, [channel, pid])
    :ok
  end

  @impl true
  def declare_exchange(channel, name, type, opts) do
    register(channel, :declare_exchange, [channel, name, type, opts])
    :ok
  end

  @impl true
  def bind_exchange(channel, dest, source, opts) do
    register(channel, :bind_exchange, [channel, dest, source, opts])
    :ok
  end

  @impl true
  def declare_queue(channel, name, opts)

  def declare_queue(channel, "", opts) do
    generated_name = "generated_name_#{:rand.uniform(10000)}"
    register(channel, :declare_queue, [channel, "", opts])
    {:ok, generated_name}
  end

  def declare_queue(channel, name, opts) do
    register(channel, :declare_queue, [channel, name, opts])
    {:ok, name}
  end

  @impl true
  def bind_queue(channel, queue, exchange, options) do
    Channel.register(channel, :bind_queue, [channel, queue, exchange, options])
    :ok
  end

  @impl true
  def unbind_queue(channel, queue, exchange, options) do
    Channel.register(channel, :unbind_queue, [channel, queue, exchange, options])
    :ok
  end

  @impl true
  def delete_queue(channel, queue, options) do
    Channel.register(channel, :delete_queue, [channel, queue, options])
    # For the sandbox always return 0 messages
    {:ok, %{message_count: 0}}
  end

  @impl true
  def publish(channel, exchange, routing_key, payload, opts) do
    register(channel, :publish, [channel, exchange, routing_key, payload, opts])
  end

  @impl true
  def consume(channel, queue, consumer, options) do
    consumer_tag = "consumer_#{:rand.uniform(10000)}"
    register(channel, :consume, [channel, queue, consumer, consumer_tag, options])
    {:ok, consumer_tag}
  end

  @impl true
  def qos(channel, opts) do
    register(channel, :qos, [channel, opts])
    :ok
  end

  @impl true
  def ack(channel, delivery_tag, opts) do
    register(channel, :ack, [channel, delivery_tag, opts])
  end

  @impl true
  def nack(channel, delivery_tag, opts) do
    register(channel, :nack, [channel, delivery_tag, opts])
  end

  @impl true
  def reject(channel, delivery_tag, opts) do
    register(channel, :reject, [channel, delivery_tag, opts])
  end

  @impl true
  def handle_message(message) do
    case message do
      {:consume_ok, _meta} -> message
      {:deliver, _payload, _meta} -> message
      {:cancel_ok, _meta} -> message
      {:cancel, _meta} -> message
      {:return, _payload, _meta} -> message
      _ -> :unknown
    end
  end
end
