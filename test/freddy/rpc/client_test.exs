defmodule Freddy.RPC.ClientTest do
  use Freddy.ConnCase

  alias Freddy.RPC.Client

  defmodule TestClient do
    use Client

    def start_link(conn, config, pid \\ self(), opts \\ []) do
      Client.start_link(__MODULE__, conn, config, pid, opts)
    end

    def handle_connected(pid) do
      send(pid, :connected)
      {:noreply, pid}
    end

    def handle_disconnected(reason, pid) do
      send(pid, {:disconnected, reason})
      {:noreply, pid}
    end

    def handle_ready(meta, pid) do
      send(pid, {:ready, meta})
      {:noreply, pid}
    end

    def before_request(%{options: opts} = request, pid) do
      send(pid, {:before_request, request})

      case opts[:hook] do
        {:modify, fields} -> {:ok, Map.merge(request, fields), pid}
        {:stop, reason, reply} -> {:stop, reason, reply, pid}
        {:reply, reply} -> {:reply, reply, pid}
        nil -> {:ok, pid}
      end
    end

    def get_state(client) do
      Client.call(client, :get_state)
    end

    def handle_call(:get_state, _from, pid) do
      {:reply, pid, pid}
    end
  end

  test "calls handle_connected/1 when RabbitMQ connection is established", %{conn: conn} do
    start_client(conn, [])
    assert_receive :connected
  end

  test "starts consumption and sets up return handler on start", %{conn: conn, history: history} do
    rpc_client = start_client(conn, [])
    assert_receive {:ready, %{resp_queue: resp_queue}}
    %{consumer_tag: consumer_tag, name: resp_queue_name} = resp_queue

    assert [
             {:open_channel, [_conn], {:ok, channel}},
             {:monitor_channel, [channel], _ref},
             {:declare_server_named_queue, [channel, [auto_delete: true, exclusive: true]],
              {:ok, ^resp_queue_name, _queue_info}},
             {:consume, [channel, ^resp_queue_name, ^rpc_client, [no_ack: true]],
              {:ok, ^consumer_tag}},
             {:register_return_handler, [channel, ^rpc_client], :ok}
           ] = Adapter.Backdoor.last_events(history, 5)
  end

  test "calls handle_disconnected/2 when RabbitMQ connection is disrupted", %{conn: conn} do
    start_client(conn, [])
    assert_receive {:ready, %{resp_queue: %{chan: chan}}}

    Adapter.Backdoor.crash(chan.given, :simulated_crash)
    assert_receive {:disconnected, :simulated_crash}
  end

  describe "before_request/3" do
    test "sends original payload and original routing key on {:ok, state}", %{
      conn: conn,
      history: history
    } do
      rpc_client = start_client(conn, [])

      routing_key = "TestQueue"
      payload = %{type: "action", key: "value"}
      encoded_payload = Poison.encode!(payload)

      request =
        Task.async(fn ->
          Freddy.RPC.Client.request(rpc_client, routing_key, payload)
        end)

      assert_receive {:before_request,
                      %{payload: ^payload, routing_key: ^routing_key, options: _opts}}

      assert nil == Task.yield(request, 100)

      assert {:publish, [_chan, "" = _exchange, ^encoded_payload, ^routing_key, options], :ok} =
               Adapter.Backdoor.last_event(history)

      %{correlation_id: correlation_id} = assert_options_injected(options)
      respond_to(rpc_client, %{success: true, output: 42}, %{correlation_id: correlation_id})

      assert {:ok, 42} = Task.await(request)
    end

    test "sends modified routing key, payload and options on {:ok, request, state}", %{
      conn: conn,
      history: history
    } do
      rpc_client = start_client(conn, [])

      original_routing_key = "TestQueue"
      modified_routing_key = "TestQueue2"

      original_payload = %{type: "action", key: "value"}
      modified_payload = %{type: "another_action", key: "new_value"}
      encoded_payload = Poison.encode!(modified_payload)

      modified_options = [app_id: "testapp2"]

      options = [
        app_id: "testapp",
        hook:
          {:modify,
           %{
             payload: modified_payload,
             routing_key: modified_routing_key,
             options: modified_options
           }}
      ]

      request =
        Task.async(fn ->
          Freddy.RPC.Client.request(rpc_client, original_routing_key, original_payload, options)
        end)

      assert_receive {:before_request,
                      %{
                        payload: ^original_payload,
                        routing_key: ^original_routing_key,
                        options: given_options
                      }}

      assert given_options[:app_id] == "testapp"
      assert Keyword.has_key?(given_options, :correlation_id)

      assert nil == Task.yield(request, 100)

      assert {:publish,
              [_chan, "" = _exchange, ^encoded_payload, ^modified_routing_key, published_options],
              :ok} = Adapter.Backdoor.last_event(history)

      %{correlation_id: correlation_id} = assert_options_injected(published_options)
      respond_to(rpc_client, %{success: true, output: 42}, %{correlation_id: correlation_id})

      assert {:ok, 42} = Task.await(request)
    end

    test "returns reply on {:reply, reply, state}", %{conn: conn} do
      rpc_client = start_client(conn, [])

      assert :response =
               Freddy.RPC.Client.request(rpc_client, "key", "payload", hook: {:reply, :response})
    end

    test "stops the process on {:stop, reason, reply, state}", %{conn: conn} do
      rpc_client = start_client(conn, [])

      ref = Process.monitor(rpc_client)

      assert :response =
               Freddy.RPC.Client.request(
                 rpc_client,
                 "key",
                 "payload",
                 hook: {:stop, :normal, :response}
               )

      assert_receive {:DOWN, ^ref, :process, ^rpc_client, :normal}
    end
  end

  test "returns `{:error, :timeout}` on timeouts", %{conn: conn} do
    rpc_client = start_client(conn, timeout: 1)
    routing_key = "TestQueue"
    initial_state = TestClient.get_state(rpc_client)

    request =
      Task.async(fn ->
        Freddy.RPC.Client.request(rpc_client, routing_key, %{})
      end)

    assert {:ok, result} = Task.yield(request, 100)
    assert {:error, :timeout} == result

    assert ^initial_state = TestClient.get_state(rpc_client)
  end

  test "returns `{:error, :no_route}` on return", %{conn: conn} do
    rpc_client = start_client(conn, [])
    routing_key = "TestQueue"
    initial_state = TestClient.get_state(rpc_client)

    request =
      Task.async(fn ->
        Freddy.RPC.Client.request(rpc_client, routing_key, %{})
      end)

    assert_receive {:before_request, %{options: [correlation_id: correlation_id]}}

    send(rpc_client, {:return, "", %{correlation_id: correlation_id}})
    assert {:error, :no_route} = Task.await(request)

    assert ^initial_state = TestClient.get_state(rpc_client)
  end

  defp start_client(conn, config) do
    {:ok, rpc_client} = TestClient.start_link(conn, config, self())

    # Emulate RabbitMQ confirmation
    send(rpc_client, {:consume_ok, %{}})

    rpc_client
  end

  defp assert_options_injected(options) do
    assert options[:mandatory]
    assert options[:content_type] == "application/json"
    assert Keyword.has_key?(options, :expiration)
    assert Keyword.has_key?(options, :reply_to)
    assert Keyword.has_key?(options, :correlation_id)

    Map.new(options)
  end

  defp respond_to(rpc_client, payload, meta) do
    send(rpc_client, {:deliver, Poison.encode!(payload), meta})
  end
end
