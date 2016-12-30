defmodule Freddy.RPC.ClientTest do
  use ExUnit.Case

  alias Freddy.Conn.{Chan, Queue}

  @queue_name "TestQueue"

  defmodule TestConnecton do
    use Freddy.Conn, otp_app: :freddy
  end

  defmodule TestClient do
    use Freddy.RPC.Client,
        connection: TestConnecton,
        queue: "TestQueue"
  end

  defmodule TestProducer do
    use Freddy.GenProducer
  end

  defmodule TestServer do
    use Freddy.GenConsumer, producer: nil

    def init_worker(state, opts) do
      state = super(state, opts)
      {:ok, producer} = TestProducer.start_link(state.conn)
      %{state | producer: producer}
    end

    def handle_message(payload, %{correlation_id: correlation_id, reply_to: reply_to}, state = %{producer: producer}) do
      TestProducer.produce(producer, reply_to, payload, correlation_id: correlation_id)

      {:ack, state}
    end
  end

  test "receives response from remote service" do
    {:ok, server_conn} = Freddy.Conn.start_link()

    {:ok, server} = TestServer.start_link(server_conn, queue: @queue_name)
    TestClient.start_link()

    :timer.sleep(500)

    payload = "ping"
    response = TestClient.call(payload)

    assert response == {:ok, payload}

    TestServer.stop(server)

    # delete test queue
    {:ok, chan} = Freddy.Conn.open_channel(server_conn)
    Queue.delete(chan, @queue_name)

    TestClient.stop()
    Freddy.Conn.stop(server_conn)
  end

  test "receives {:error, :timeout} if remote service is unresponsive" do
    TestClient.start_link()

    # create test queue
    {:ok, chan} = Chan.open(TestConnecton)
    Queue.declare(chan, @queue_name)

    # wait until bind succeeds
    :timer.sleep(500)

    payload = "ping"
    response = TestClient.call(payload, timeout: 100)

    assert response == {:error, :timeout}

    # delete test queue after test
    Queue.delete(chan, @queue_name)

    TestClient.stop()
  end

  test "receives {:error, :no_route} if queue doesn't exist" do
    TestClient.start_link()

    # wait until client is connected
    :timer.sleep(200)

    response = TestClient.call("ping", timeout: 100)

    assert response == {:error, :no_route}

    TestClient.stop()
  end
end
