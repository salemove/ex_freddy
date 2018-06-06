# Freddy

[![Build Status](https://travis-ci.org/salemove/ex_freddy.svg?branch=master)](https://travis-ci.org/salemove/ex_freddy)

OTP behaviours for creating AMQP publishers and consumers.

**The project is in active development stage, expect breaking changes between minor versions up to 1.0.**

## Installation

Add `freddy` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [{:freddy, "~> 0.11.0"}]
end
```

## Stable connection

Neither [official RabbitMQ client](https://github.com/rabbitmq/rabbitmq-erlang-client),
nor its Elixir wrapper [amqp](https://github.com/pma/amqp) provide an out-of-box way
to create a stable monitored connection to RabbitMQ server, which will be gracefully
reestablished after server restart or intermittent network failures.

Freddy attempts to provide such abstraction, which is called `Freddy.Connection`. It is
a standard OTP-compliant process that can be easily integrated into OTP supervision tree
using standard capabilities.

All Freddy behaviors (publishers and consumers) require `Freddy.Connection`.

The connection process can be started like this:

```elixir
{:ok, conn} = Freddy.Connection.start_link(config)
```

Check out [`AMQP.Connection.open/1`](https://hexdocs.pm/amqp/AMQP.Connection.html#open/1) for
available options.

Add this process to an OTP application supervision tree:

```elixir
defmodule MyApp do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(Freddy.Connection, [[], [name: Freddy.Connection]])
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

We recommend to start `Freddy.Connection` and all your publishers and consumers in the OTP
supervision tree. Ideally connection and dependent processes should be grouped in one supervisor
with restart strategy `:rest_for_one`.

## Publishers

Freddy provides a behaviour module [`Freddy.Publisher`](https://hexdocs.pm/freddy/Freddy.Publisher.html)
to implement your own stateful publishers.

Check out [the behaviour documentation](https://hexdocs.pm/freddy/Freddy.Publisher.html) for information
about all available callbacks.

By default publisher processes encode message payload to JSON before sending the message to RabbitMQ server,
it is responsibility of consumers to decode message back. This behaviour can be changed by redefining
the default implementation of `Freddy.Publisher.encode_message/4` callback.

### Example

Below is an example of how to implement a publishing process that queues up messages when RabbitMQ
connection is disrupted (instead of silently dropping them):

```elixir
defmodule ReliableBroadcaster do
  use Freddy.Publisher

  @exchange %Freddy.Core.Exchange{name: "notifications", type: :fanout, opts: [durable: true]}
  @config [exchange: @exchange]

  def start_link(connection, opts \\ []) do
    Freddy.Publisher.start_link(__MODULE__, connection, @config, nil, opts)
  end

  @impl true
  def init(_) do
    state = %{connected: false, queue: :queue.new()}
    {:ok, state}
  end

  @impl true
  # This function is called after an exchange has been declared
  def handle_connected(meta, %{queue: queue} = state) do
    new_state = %{state | connected: true, queue: drain_queue(queue, meta)}
    {:noreply, new_state}
  end

  @impl true
  # This function is called right after disconnect
  def handle_disconnected(_reason, state) do
    {:noreply, %{state | connected: false}}
  end

  @impl true
  # Catch messages before publication and queue them up if connection is not available
  def before_publication(
    payload, routing_key, opts, %{connected: connected?, queue: queue} = state
  ) do
    if connected? do
      message = {payload, routing_key, opts}
      {:ignore, %{state | queue: :queue.in(message, queue)}}
    else
      {:ok, state}
    end
  end

  defp drain_queue(queue, meta) do
    case :queue.out(queue) do
      {{:value, {payload, routing_key, opts}}, new_queue} ->
        Freddy.Publisher.publish(meta, payload, routing_key, opts)
        drain_queue(new_queue, meta)

      {:empty, empty_queue} ->
        empty_queue
    end
  end
end
```

## Consumers

Stateful consumer processes are implemented with [`Freddy.Consumer`](https://hexdocs.pm/freddy/Freddy.Consumer.html)
behaviour module.

Check out [the behaviour documentation](https://hexdocs.pm/freddy/Freddy.Consumer.html) for
information about all available callbacks.

Consumer process typically works as follows:

1. After initialization consumer opens an AMQP channel
2. An exchange and a queue are declared using the opened channel
3. The declared queue is bound to the exchange (see
   [RabbitMQ routing tutorial](https://www.rabbitmq.com/tutorials/tutorial-four-elixir.html)),
4. The consumer process starts consumption from the queue
5. Broker confirms that consumer process is registered on the server
6. Messages from the queue are delivered to the consumer process
7. When consumer has successfully processed a message, it acknowledges the message on server,
   and the server removes the message from the queue.

### Message format

By default consumer processes assume that incoming messages payload are encoded into JSON and decode
them before starting processing. This behaviour can be changed by redefining the default implementation
of `Freddy.Consumer.decode_message/3` callback.

### Example

This is an example of a process that creates an exclusive queue with server-generated name,
binds this queue to fanout exchange "notifications" and processes each message in a separate
asynchronous task.

Please note that as we process messages asynchronously and we don't consume messages with `:no_ack`
option, we must explicitly acknowledge or reject processed messages using `Freddy.Consumer.ack/2` or
`Freddy.Consumer.reject/2`.

The chosen approach is very naive and we do not recommend to use this code in production, it
is here only for educational purposes.

```elixir
defmodule NotificationsProcessor do
  use Freddy.Consumer

  @config [
    exchange: [name: "notifications", type: :fanout],
    queue: [opts: [exclusive: true, auto_delete: true]],
    qos: [prefetch_count: 10],
    routing_keys: ["#"]
  ]

  def start_link(conn, handler_mfa) do
    Freddy.Consumer.start_link(__MODULE__, conn, @config, handler_mfa)
  end

  @impl true
  def init(handler) do
    {:ok, handler}
  end

  @impl true
  def handle_message(payload, %{routing_key: key} = meta, {m, f, a} = handler) do
    Task.start_link(fn ->
      try do
        apply(m, f, [payload, key | a])

        Freddy.Consumer.ack(meta)
      rescue _error ->
        # we might want to log error here too
        Freddy.Consumer.reject(meta, requeue: true)
      end
    end)

    {:noreply, state}
  end
end
```

## RPC Client

[RPC Client](https://www.rabbitmq.com/tutorials/tutorial-six-elixir.html) in a nutshell is a combination of
consumer and publisher. A process publishes RPC requests into default or any other exchange and expects a
server to publish response message to a special anonymous queue from which an RPC client process consumes.

Each request contains a name of reply queue and a correlation ID - an identifier which allows RPC
client to understand for which client the response has arrived. When server sends a reply, it publishes a
message into default exchange with a routing key equal to the name of the client reply queue and copies
correlation ID from the request to the response message.

A diagram below illustrates an RPC request-response lifecycle:

```
  +------------+             +----------------+
  |   Client   |------------>|  Pub exchange  |
  +------------+             +----------------+
         ^                            |
         |                            |
         |                            v
  +-------------+            +----------------+
  | Reply queue |            |  Server queue  |
  +-------------+            +----------------+
         ^                            |
         |                            |
         |                            v
+----------------+           +----------------+
|Default exchange|<----------|   RPC Server   |
+----------------+           +----------------+
```

### Example

This is an example of RPC client that publishes requests to the default exchange, logs unsuccessful requests
and emits response time to a StatsD server.

```elixir
defmodule RPC.Client do
  use Freddy.RPC.Client

  require Logger

  alias Freddy.RPC.Request

  @server_queue "RemoteService"

  def start_link(conn, opts \\ []) do
    Freddy.RPC.Client.start_link(__MODULE__, conn, [], nil, opts)
  end

  def request(client, payload) do
    Freddy.RPC.Client.request(client, @server_queue, payload)
  end

  @impl true
  def on_timeout(request, state) do
    Logger.warn("Request to server #{request.routing_key} timed out after #{Request.duration(request)} ms")
    {:reply, {:error, :timeout}, state}
  end

  @impl true
  def on_return(request, state) do
    Logger.warn("Request to server #{request.routing_key} couldn't be routed")
    {:reply, {:error, :no_route}, state}
  end

  @impl true
  def on_response(response, request, state) do
    send_metrics(request)
    {:reply, response, state}
  end

  defp send_metrics(request) do
    MyApp.Statix.histogram("rpc.request", Request.duration(request), tags: ["server:#{request.routing_key}"])
  end
end
```

### Testing

We recommend you to structure your code in such way that your test environment will not use real RPC client.

For example, you can create a client behavior and use [Mox](https://github.com/plataformatec/mox) to mock all
calls to a client. This way you can test how your code communicates with RPC client. Please refer to
[Mox documentation](https://hexdocs.pm/mox/Mox.html) for more information about mocks and explicit contracts.

If you need to test RPC client itself, you can hook into request lifecycle and use `before_request/2` callback
to return required responses. It is recommended to use fake connection in test environment:

```elixir
defmodule MockClient do
  use Freddy.RPC.Client

  def start_link(conn) do
    Freddy.RPC.Client.start_link(__MODULE__, conn, [], [])
  end

  def flush(client) do
    Freddy.RPC.Client.call(client, :flush)
  end

  def before_request(request, sink) do
    {:reply, :ok, [request | sink]}
  end

  def handle_call(:flush, sink) do
    {:reply, Enum.reverse(sink), []}
  end
end
```

And use it in tests:
```elixir
test "sends an RPC request" do
  {:ok, conn} = Freddy.Connection.start_link(adapter: :sandbox)
  {:ok, client} = MockClient.start_link(conn)
  MyLib.call(client: client)

  assert [%{routing_key: "server"}] = MockClient.flush(client)
end
```
