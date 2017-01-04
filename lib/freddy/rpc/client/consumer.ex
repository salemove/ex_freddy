defmodule Freddy.RPC.Client.Consumer do
  use Freddy.GenConsumer, client: nil

  alias Freddy.RPC.Client

  require Logger

  def init_worker(state, opts) do
    state = super(state, opts)
    client = Keyword.fetch!(opts, :client)

    %{state | client: client}
  end

  def queue_spec(_opts),
    do: {"", [exclusive: true]}

  def handle_ready(_meta, state = %{queue: queue}) do
    Logger.info "Consuming messages from #{queue}"
    {:noreply, state}
  end

  def handle_message(payload, meta = %{correlation_id: correlation_id}, state = %{client: client}) do
    Client.reply(client, correlation_id, {:ok, payload, meta})
    {:noreply, state}
  end

  def handle_exception(error, state) do
    Logger.error("Exception in consumer: #{inspect error}")
    {:stop, :error, state}
  end
end
