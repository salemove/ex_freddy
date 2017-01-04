defmodule Freddy.RPC.Client.Request do
  defstruct client: nil, # RPC Client pid
            payload: nil, # Message payload
            opts: nil, # Message properties
            queue: nil, # Destination queue
            status: nil, # Response status (:ok | :error)
            error: nil, # Error reason (if status = :error)
            env: nil # Additional request options (map), can be used internally by middlewares to pass non-standard state between each other

  alias __MODULE__
  alias Freddy.RPC.Client

  def new(client, payload, opts) do
    %Request{client: client, payload: payload, opts: opts, env: Map.new, queue: Client.destination_queue(client)}
  end

  def update_payload(request, payload) do
    Map.put(request, :payload, payload)
  end

  def put_env(request, key, value) do
    Map.update!(request, :env, &Map.put(&1, key, value))
  end

  def put_opt(request, key, value) do
    Map.update!(request, :opts, &Keyword.put(&1, key, value))
  end
end
