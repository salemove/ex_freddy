defmodule Freddy.Conn.Adapter.Sandbox.Broker do
  use GenServer

  alias Freddy.Conn.Adapter.Sandbox.Channel

  defmodule Consumer do
    defstruct [:queue, :pid, :consumer_tag]

    def register(broker = %{consumers: consumers, consumer_tag: tag}, consumer) do
      consumer_tag = tag + 1
      consumer = %{consumer | consumer_tag: consumer_tag}
      send(consumer.pid, {:basic_consume_ok, %{consumer_tag: consumer_tag}})
      %{broker | consumers: [consumer | consumers], consumer_tag: consumer_tag}
    end

    def notify(broker = %{delivery_tag: tag}, _consumer = %{pid: pid}, payload, opts) do
      delivery_tag = tag + 1
      properties = opts |> Map.new() |> Map.put(:delivery_tag, delivery_tag)
      send(pid, {:basic_deliver, payload, properties})
      %{broker | delivery_tag: delivery_tag}
    end
  end

  defstruct [:consumers, :messages, :delivery_tag, :consumer_tag]

  alias __MODULE__

  def start(opts \\ []) do
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 5672)
    name = String.to_atom("#{__MODULE__}.#{host}:#{port}")

    case GenServer.start(__MODULE__, [], name: name) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  def consume(broker, queue, consumer) do
    GenServer.call(broker, {:consume, queue, consumer})
  end

  def publish(broker, chan, queue, payload, opts) do
    GenServer.cast(broker, {:publish, chan, queue, payload, opts})
  end

  def messages(broker) do
    GenServer.call(broker, :messages)
  end

  def stop(broker, reason) do
    GenServer.stop(broker, reason)
  end

  # GenServer callbacks

  def init(_) do
    {:ok, %Broker{consumers: [], messages: [], delivery_tag: 0, consumer_tag: 0}}
  end

  def handle_call({:consume, queue, pid}, _from, broker) do
    Process.monitor(pid)

    consumer = %Consumer{queue: queue, pid: pid}
    broker = Consumer.register(broker, consumer)

    {:reply, {:ok, broker.consumer_tag}, broker}
  end

  def handle_call(:messages, _from, broker = %{messages: messages}) do
    {:reply, Enum.reverse(messages), broker}
  end

  def handle_cast({:publish, chan, queue, payload, opts}, broker) do
    subscribers = subscribers(broker, queue)

    new_state =
      if length(subscribers) > 0 do
        deliver_message(broker, subscribers, {payload, opts})
      else
        return_message(broker, chan, {payload, opts})
      end

    {:noreply, register_message(new_state, {payload, opts})}
  end

  # If consumer goes down, remove it from the broker
  def handle_info({:DOWN, ref, :process, consumer_pid, _reason}, broker = %{consumers: consumers}) do
    Process.demonitor(ref)
    new_consumers = Enum.reject(consumers, &(&1.pid == consumer_pid))
    {:noreply, %{broker | consumers: new_consumers}}
  end

  defp register_message(broker = %{messages: messages}, message) do
    %{broker | messages: [message | messages]}
  end

  defp subscribers(_broker = %{consumers: consumers}, queue) do
    for consumer <- consumers,
        consumer.queue == queue,
        do: consumer
  end

  defp deliver_message(broker, [consumer | rest], message = {payload, opts}) do
    broker = Consumer.notify(broker, consumer, payload, opts)
    deliver_message(broker, rest, message)
  end

  defp deliver_message(broker, [], _) do
    broker
  end

  defp return_message(broker, chan, {payload, opts}) do
    Channel.return_message(chan, payload, opts)
    broker
  end
end
