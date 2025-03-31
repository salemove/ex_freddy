defmodule Freddy.Integration.RPC.ClientTest do
  use Freddy.IntegrationCase

  defmodule TestClient do
    use Freddy.RPC.Client
    alias Freddy.RPC.Request

    @config [exchange: [name: "freddy-rpc-test-exchange", type: :direct]]

    def start_link(conn, pid, opts \\ []) do
      Freddy.RPC.Client.start_link(__MODULE__, conn, Keyword.merge(@config, opts), pid)
    end

    defdelegate request(client, routing_key, payload, opts \\ []), to: Freddy.RPC.Client

    @impl true
    def init(pid) do
      send(pid, :init)
      {:ok, pid}
    end

    @impl true
    def handle_connected(meta, pid) do
      send(pid, {:connected, meta})
      {:noreply, pid}
    end

    @impl true
    def handle_ready(%{queue: queue} = _meta, pid) do
      send(pid, {:ready, queue.name})
      {:noreply, pid}
    end

    @impl true
    def handle_disconnected(reason, pid) do
      send(pid, {:disconnected, reason})
      {:noreply, pid}
    end

    @impl true
    def before_request(request, pid) do
      case Request.get_option(request, :on_before_action) do
        {:change, new_payload} -> {:ok, Request.set_payload(request, new_payload), pid}
        {:reply, response} -> {:reply, response, pid}
        _other -> super(request, pid)
      end
    end

    @impl true
    def on_response(response, request, pid) do
      case Request.get_option(request, :on_response_action) do
        {:reply, response} -> {:reply, response, pid}
        _other -> super(response, request, pid)
      end
    end

    @impl true
    def on_timeout(request, pid) do
      case Request.get_option(request, :on_timeout_action) do
        {:reply, response} -> {:reply, response, pid}
        _other -> super(request, pid)
      end
    end

    @impl true
    def on_return(request, pid) do
      case Request.get_option(request, :on_return_action) do
        {:reply, response} -> {:reply, response, pid}
        _other -> super(request, pid)
      end
    end

    @impl true
    def handle_call(:call, _from, pid) do
      {:reply, :response, pid}
    end

    @impl true
    def handle_cast(:cast, pid) do
      send(pid, :cast)
      {:noreply, pid}
    end

    @impl true
    def handle_info(:info, pid) do
      send(pid, :info)
      {:noreply, pid}
    end

    @impl true
    def terminate(reason, pid) do
      send(pid, {:terminate, reason})
    end
  end

  # simple echo server
  defmodule TestServer do
    use Freddy.RPC.Server

    @config [
      exchange: [name: "freddy-rpc-test-exchange", type: :direct],
      queue: [opts: [auto_delete: true]],
      routing_keys: ["server"]
    ]

    def start_link(conn, pid) do
      Freddy.RPC.Server.start_link(__MODULE__, conn, @config, pid)
    end

    def handle_ready(_meta, pid) do
      send(pid, :server_ready)
      {:noreply, pid}
    end

    def handle_request(%{"action" => "timeout"}, _meta, pid) do
      {:noreply, pid}
    end

    def handle_request(payload, _meta, pid) do
      {:reply, payload, pid}
    end
  end

  setup context do
    connection = context[:connection]
    client_opts = context[:client_options] || []

    {:ok, client} = TestClient.start_link(connection, self(), client_opts)
    context = Map.put(context, :client, client)

    context =
      if context[:server] do
        assert_receive :init
        assert_receive {:connected, _}
        assert_receive {:ready, _}

        {:ok, server} = TestServer.start_link(connection, self())
        assert_receive :server_ready

        Map.put(context, :server, server)
      else
        context
      end

    {:ok, context}
  end

  test "init/1 is called when the process starts" do
    assert_receive :init
  end

  test "handle_connected/2 is called after init/1" do
    assert_receive :init
    assert_receive {:connected, %{queue: _, exchange: _}}
  end

  test "handle_ready/2 is called when client is ready to consume response messages" do
    assert_receive :init
    assert_receive {:connected, _}
    assert_receive {:ready, "amq.gen-" <> _random_name}
  end

  test "before_request/2 can reply early", %{client: client} do
    assert_receive {:ready, _}

    assert TestClient.request(
             client,
             "_routing_key",
             "_payload",
             on_before_action: {:reply, :early_response}
           ) == :early_response
  end

  @tag server: true
  test "before_request/2 can modify the request", %{client: client} do
    response_payload = %{success: true, response: "new_payload"}

    assert {:ok, %{"response" => "new_payload"}} =
             TestClient.request(
               client,
               "server",
               "_payload",
               on_before_action: {:change, response_payload}
             )
  end

  @tag server: true
  test "on_response/2 can change a response", %{client: client} do
    payload = %{success: true, response: "payload"}
    changed_response = :new_response

    assert TestClient.request(
             client,
             "server",
             payload,
             on_response_action: {:reply, changed_response}
           ) == changed_response
  end

  @tag server: true
  test "on_return/2 returns {:error, :no_route} by default", %{client: client} do
    assert {:error, :no_route} = TestClient.request(client, "unknown_route", "_payload")
  end

  @tag server: true
  test "on_return/2 reply is configurable", %{client: client} do
    assert :response =
             TestClient.request(
               client,
               "unknown_route",
               "_payload",
               on_return_action: {:reply, :response}
             )
  end

  @tag server: true, client_options: [timeout: 100]
  test "on_timeout/2 returns {:error, :timeout} by default", %{client: client} do
    request =
      Task.async(fn ->
        TestClient.request(client, "server", %{action: :timeout})
      end)

    assert {:ok, {:error, :timeout}} = Task.yield(request, 200)
  end

  @tag server: true
  test "on_timeout/2 returns {:error, :timeout} by default when configured per-request", %{
    client: client
  } do
    request =
      Task.async(fn ->
        TestClient.request(client, "server", %{action: :timeout}, timeout: 100)
      end)

    assert {:ok, {:error, :timeout}} = Task.yield(request, 200)
  end

  @tag server: true, client_options: [timeout: 100]
  test "on_timeout/2 reply is configurable", %{client: client} do
    request =
      Task.async(fn ->
        TestClient.request(
          client,
          "server",
          %{action: :timeout},
          on_timeout_action: {:reply, :response}
        )
      end)

    assert {:ok, :response} = Task.yield(request, 200)
  end

  test "handle_call/3 is called on Freddy.RPC.Client.call", %{client: client} do
    assert :response = Freddy.RPC.Client.call(client, :call)
  end

  test "handle_cast/2 is called on Freddy.RPC.Client.cast", %{client: client} do
    assert :ok = Freddy.RPC.Client.cast(client, :cast)
    # synchronize with client
    _ = :sys.get_state(client)
    assert_receive :cast
  end

  test "handle_info/2 is called on other messages", %{client: client} do
    send(client, :info)
    # synchronize with client
    _ = :sys.get_state(client)
    assert_receive :info
  end

  test "terminate/2 is called when the process stops", %{client: client} do
    Freddy.RPC.Client.stop(client, :normal)
    assert_receive {:terminate, :normal}
  end

  @tag server: true, capture_log: true
  test "handle_disconnected/2 callback is called when connection is disrupted", %{
    connection: connection
  } do
    assert {:ok, conn} = Freddy.Connection.get_connection(connection)

    ref = Process.monitor(conn)
    :amqp_gen_connection.server_close(conn, {:"connection.close", ~c"Good bye", 302, 0, 0})
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert_receive {:disconnected,
                    {:shutdown, {:connection_closing, {:server_initiated_close, ~c"Good bye", 302}}}}

    assert_receive {:ready, _}, 5000
    refute_receive :init
  end

  test "request/5 returns {:error, :not_connected} when client is in disconnected state", %{
    connection: connection,
    client: client
  } do
    assert_receive {:connected, _}
    Freddy.Connection.close(connection)
    assert_receive {:disconnected, _}
    assert {:error, :not_connected} = TestClient.request(client, "_server", "_payload")
  end

  @tag server: true, capture_log: true
  test "process stops if client can't declare an exchange due to permanent error", %{
    connection: connection
  } do
    {:ok, pid} =
      Freddy.RPC.Client.start(
        TestClient,
        connection,
        [exchange: [name: "amq.direct", type: :topic]],
        self()
      )

    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, :precondition_failed}
  end

  @tag server: true
  test "returns {:ok, output} when server responds with %{success: true, output: result}", %{
    client: client
  } do
    payload = %{success: true, output: "payload"}
    assert {:ok, "payload"} = TestClient.request(client, "server", payload)
  end

  @tag server: true
  test "returns {:ok, payload} when server responds with %{success: true, ...payload}", %{
    client: client
  } do
    payload = %{success: true, result: "payload"}
    assert {:ok, %{"result" => "payload"}} = TestClient.request(client, "server", payload)
  end

  @tag server: true
  test "returns {:error, :invalid_request, error} when server responds with %{success: false, error: error}",
       %{client: client} do
    payload = %{success: false, error: "error"}
    assert {:error, :invalid_request, "error"} = TestClient.request(client, "server", payload)
  end

  @tag server: true
  test "returns {:error, :invalid_request, payload} when server responds with %{success: false, ...payload}",
       %{client: client} do
    payload = %{success: false, result: "error"}

    assert {:error, :invalid_request, %{"result" => "error"}} =
             TestClient.request(client, "server", payload)
  end

  @tag server: true
  test "returns {:ok, payload} when server responds with arbitrary payload",
       %{client: client} do
    payload = "payload"
    assert {:ok, ^payload} = TestClient.request(client, "server", payload)
  end
end
