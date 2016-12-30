defmodule Freddy.RPC.Client.Producer do
  use Freddy.GenProducer, queue: nil, reply_queue: nil, client: nil

  require Logger

  alias Freddy.RPC.Client

  @content_type "application/json"

  def queue(producer),
    do: Connection.call(producer, :queue)

  def publish(producer, payload, opts \\ []) do
    message = produce(producer, queue(producer), payload, opts)
    {:ok, message.options[:correlation_id]}
  end

  # GenProducer callbacks

  def init_worker(state, opts) do
    state = super(state, opts)

    queue = Keyword.fetch!(opts, :queue)
    client = Keyword.fetch!(opts, :client)
    reply_queue = Keyword.fetch!(opts, :reply_queue)

    %{state | queue: queue, reply_queue: reply_queue, client: client}
  end

  def handle_message(message = %{payload: payload, options: options}, state) do
    timeout = Keyword.fetch!(options, :timeout)
    correlation_id = generate_correlation_id()
    new_options = Keyword.merge(options, [
      correlation_id: correlation_id,
      # expiration value has to be a string, otherwise
      # rabbit_framing_amqp_0_9_1:encode_properties/1 (rabbit_common package) fails
      expiration: to_string(timeout),
      reply_to: state.reply_queue,
      mandatory: true,
      content_type: @content_type,
      type: "request"
    ])

    new_payload = Poison.encode!(payload)
    new_message = %{message | payload: new_payload, options: new_options}

    Logger.debug "Sending message to #{new_message.destination}, " <>
                 "payload: #{inspect payload}, " <>
                 "correlation_id: #{correlation_id}"

    {:ok, new_message, state}
  end

  def handle_no_route(_payload, properties, state = %{client: client}) do
    Client.reply(client, properties[:correlation_id], {:error, :no_route})
    {:noreply, state}
  end

  # GenServer callbacks

  def handle_call(:queue, _from, state = %{queue: queue}),
    do: {:reply, queue, state}

  # Private functions

  def generate_correlation_id,
    do: :erlang.unique_integer() |> to_string() |> Base.encode64()
end
