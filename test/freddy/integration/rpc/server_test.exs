defmodule Freddy.Integration.RPC.ServerTest do
  use Freddy.ConnectionCase

  defmodule TestServer do
    use Freddy.RPC.Server

    @config [
      queue: [name: "freddy-test-rpc-queue"]
    ]

    def start_link(conn) do
      Freddy.RPC.Server.start_link(__MODULE__, conn, @config, [])
    end

    def handle_request("error", _meta, state) do
      {:reply, {:error, "failure"}, state}
    end

    def handle_request("ping", _meta, state) do
      {:reply, {:ok, "pong"}, state}
    end
  end

  defmodule TestClient do
    use Freddy.RPC.Client

    def start_link(conn, pid) do
      Freddy.RPC.Client.start_link(__MODULE__, conn, [], pid)
    end

    def handle_ready(_meta, pid) do
      send(pid, :client_ready)
      {:noreply, pid}
    end

    def request(client, request) do
      Freddy.RPC.Client.request(client, "freddy-test-rpc-queue", request)
    end
  end

  setup %{connection: conn} do
    {:ok, _server} = TestServer.start_link(conn)
    {:ok, client} = TestClient.start_link(conn, self())

    assert_receive :client_ready

    {:ok, client: client}
  end

  test "responds to client when success", %{client: client} do
    assert {:ok, "pong"} = TestClient.request(client, "ping")
  end

  test "responds to client when failure", %{client: client} do
    assert {:error, :invalid_request, "failure"} = TestClient.request(client, "error")
  end
end
