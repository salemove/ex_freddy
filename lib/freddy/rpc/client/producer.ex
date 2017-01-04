defmodule Freddy.RPC.Client.Producer do
  use Freddy.GenProducer, client: nil

  alias Freddy.RPC.Client

  def init_worker(state, opts) do
    state = super(state, opts)
    client = Keyword.fetch!(opts, :client)

    %{state | client: client}
  end

  def handle_no_route(_payload, properties, state = %{client: client}) do
    Client.reply(client, properties[:correlation_id], {:error, :no_route})
    {:noreply, state}
  end
end
