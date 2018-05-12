defmodule Freddy.Notifications.BroadcasterTest do
  use Freddy.ConnCase

  defmodule TestBroadcaster do
    use Freddy.Notifications.Broadcaster
  end

  import Mock

  test "start_link/4 starts Freddy.Publisher with configured exchange", %{conn: conn} do
    with_mock Freddy.Publisher, start_link: fn _, _, _, _, _ -> :ok end do
      Freddy.Notifications.Broadcaster.start_link(TestBroadcaster, conn, nil, [])
      exchange_config = [exchange: [name: "freddy-topic", type: :topic]]

      assert called(Freddy.Publisher.start_link(TestBroadcaster, conn, exchange_config, nil, []))
    end
  end

  test "broadcast/4 delegates to Freddy.Publisher" do
    with_mock Freddy.Publisher, publish: fn _, _, _, _ -> :ok end do
      pid = self()
      routing_key = "routing-key"
      payload = %{key: "value"}

      Freddy.Notifications.Broadcaster.broadcast(pid, routing_key, payload)

      assert called(Freddy.Publisher.publish(pid, payload, routing_key, []))
    end
  end
end
