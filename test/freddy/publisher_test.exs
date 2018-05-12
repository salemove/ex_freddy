defmodule Freddy.PublisherTest do
  use Freddy.ConnCase

  defmodule TestPublisher do
    use Freddy.Publisher

    def start_link(conn, pid) do
      Freddy.Publisher.start_link(__MODULE__, conn, [exchange: [name: "test-exchange"]], pid)
    end

    def init(pid) do
      send(pid, :init)

      {:ok, pid}
    end

    def before_publication(%{action: "keep"} = payload, routing_key, opts, pid) do
      send(pid, {:before_publication, payload, routing_key, opts})

      {:ok, pid}
    end

    def before_publication(%{action: "change"} = payload, routing_key, opts, pid) do
      new_payload = %{action: "change", state: "changed"}
      new_routing_key = routing_key <> ".changed"
      new_opts = opts ++ [changed: "added"]

      send(pid, {:before_publication, payload, routing_key, opts})

      {:ok, new_payload, new_routing_key, new_opts, pid}
    end

    def handle_info(message, pid) do
      send(pid, {:info, message})

      {:noreply, pid}
    end
  end

  describe "init/1 callback" do
    test "is called on initialization", %{conn: conn} do
      publisher = start_publisher(conn)

      assert_receive :init

      tear_down(publisher)
    end
  end

  describe "before_publication/4 callback" do
    test "keeps message unchanged when returns {:ok, state}", %{conn: conn, history: history} do
      publisher = start_publisher(conn)

      payload = %{action: "keep"}
      encoded_payload = Poison.encode!(payload)
      routing_key = "routing_key"

      Freddy.Publisher.publish(publisher, payload, routing_key, mandatory: true)

      assert_receive {:before_publication, ^payload, ^routing_key, [mandatory: true]}

      sync_publisher_and_history()

      assert {:publish,
              [
                _chan,
                "test-exchange",
                ^encoded_payload,
                ^routing_key,
                [content_type: "application/json", mandatory: true]
              ], :ok} = Adapter.Backdoor.last_event(history)

      tear_down(publisher)
    end

    test "changes payload, routing_key and opts " <>
           "when returns {:ok, payload, routing_key, opts}",
         %{conn: conn, history: history} do
      publisher = start_publisher(conn)

      payload = %{action: "change"}
      expected_payload = Poison.encode!(%{action: "change", state: "changed"})
      routing_key = "routing_key"
      opts = [mandatory: true]

      Freddy.Publisher.publish(publisher, payload, routing_key, opts)

      assert_receive {:before_publication, ^payload, ^routing_key, [mandatory: true]}

      sync_publisher_and_history()

      assert {:publish,
              [
                _chan,
                "test-exchange",
                ^expected_payload,
                "routing_key.changed",
                [content_type: "application/json", mandatory: true, changed: "added"]
              ], :ok} = Adapter.Backdoor.last_event(history)

      tear_down(publisher)
    end
  end

  defp start_publisher(conn) do
    {:ok, publisher} = TestPublisher.start_link(conn, self())

    publisher
  end

  defp sync_publisher_and_history do
    Process.sleep(50)
  end

  defp tear_down(publisher) do
    Freddy.Publisher.stop(publisher)
  end
end
