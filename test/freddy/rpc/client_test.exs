defmodule Freddy.RPC.ClientTest do
  use Freddy.ConnCase

  defmodule TestServer do
    @moduledoc """
    Simple echoing RPC Server.
    """

    use Freddy.GenConsumer, producer: nil, paused?: false

    def init_worker(state, opts) do
      state = super(state, opts)
      paused? = Keyword.get(opts, :paused, false)
      %{state | paused?: paused?}
    end

    def handle_ready(_meta, state) do
      {:noreply, start_producer(state)}
    end

    def handle_message(payload, %{reply_to: reply_to, correlation_id: correlation_id}, state = %{producer: producer}) do
      unless state.paused?,
        do: Freddy.Producer.produce(producer, reply_to, payload, correlation_id: correlation_id)

      {:ack, state}
    end

    defp start_producer(state = %{conn: conn}) do
      {:ok, producer} = Freddy.Producer.start_link(conn)
      Freddy.Producer.await_connection(producer)

      %{state | producer: producer}
    end
  end

  alias Freddy.RPC.Client

  @queue "rpc-server"
  @sample_payload %{"key" => "value"}

  test "returns response from RPC server" do
    {:ok, client_conn} = open_connection()
    {:ok, server_conn} = open_connection()

    {:ok, server} = TestServer.start_link(server_conn, queue: @queue)
    {:ok, client} = Client.start_link(client_conn, @queue)

    :timer.sleep(100)

    response = Client.call(client, @sample_payload)

    assert response == {:ok, @sample_payload}

    TestServer.stop(server)
    Client.stop(client)
  end

  test "returns {:error, :no_route} if there is no consumer subscribed to a given queue" do
    {:ok, client_conn} = open_connection()
    {:ok, client} = Client.start_link(client_conn, @queue)

    :timer.sleep(100)

    response = Client.call(client, @sample_payload)

    assert response == {:error, :no_route}

    Client.stop(client)
  end

  test "returns {:error, :timeout} if RPC Server is unresponsive" do
    {:ok, client_conn} = open_connection()
    {:ok, server_conn} = open_connection()

    {:ok, server} = TestServer.start_link(server_conn, queue: @queue, paused: true)
    {:ok, client} = Client.start_link(client_conn, @queue)

    :timer.sleep(100)

    response = Client.call(client, @sample_payload, timeout: 50)

    assert response == {:error, :timeout}

    TestServer.stop(server)
    Client.stop(client)
  end
end
