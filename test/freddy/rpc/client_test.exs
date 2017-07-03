defmodule Freddy.RPC.ClientTest do
  use Freddy.ConnCase

  alias Freddy.RPC.Client

  defmodule TestClient do
    use Client

    def start_link(conn, config, initial, opts \\ []) do
      Client.start_link(__MODULE__, conn, config, initial, opts)
    end
  end

  test "sends request to specified queue", %{conn: conn, history: history} do
    queue_name = "TestQueue"
    rpc_client = start_client(conn, [routing_key: queue_name])

    request = Task.async fn ->
      Freddy.RPC.Client.request(rpc_client, %{type: "action", key: "value"})
    end

    assert nil == Task.yield(request, 100)

    expected_payload = ~s[{"type":"action","key":"value"}]

    assert [{:open_channel,
              [_conn],
              {:ok, channel}},
            {:monitor_channel,
              [channel],
              _ref},
            {:declare_server_named_queue,
              [channel, [auto_delete: true, exclusive: true]],
              {:ok, resp_queue_name, _queue_info}},
            {:consume,
              [channel, resp_queue_name, ^rpc_client, [no_ack: true]],
              {:ok, _consumer_tag}},
            {:register_return_handler,
              [channel, ^rpc_client],
              :ok},
            {:publish,
              [channel, "" = _exchange, ^expected_payload, "TestQueue", [
                mandatory: true,
                content_type: "application/json",
                expiration: "3000",
                type: "request",
                reply_to: resp_queue_name,
                correlation_id: correlation_id
              ]],
              :ok}] = Adapter.Backdoor.last_events(history, 6)

    response_payload = ~s[{"success":true,"output":42}]

    send(rpc_client, {:deliver, response_payload, %{correlation_id: correlation_id}})

    assert {:ok, 42} = Task.await(request)
  end

  test "returns `{:error, :timeout}` on timeouts", %{conn: conn} do
    rpc_client = start_client(conn, [routing_key: "TestQueue", timeout: 1])
    request = Task.async fn ->
      Freddy.RPC.Client.request(rpc_client, %{})
    end

    assert {:ok, result} = Task.yield(request, 100)
    assert {:error, :timeout} == result
  end

  defp start_client(conn, config) do
    {:ok, rpc_client} = TestClient.start_link(conn, config, nil)

    # Emulate RabbitMQ confirmation
    send(rpc_client, {:consume_ok, %{}})

    rpc_client
  end
end
