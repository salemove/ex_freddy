defmodule Freddy.Adapter.SandboxTest do
  use ExUnit.Case, async: true

  import Freddy.Adapter.Sandbox

  setup do
    {:ok, conn} = open_connection([])
    {:ok, chan} = open_channel(conn)
    {:ok, conn: conn, chan: chan}
  end

  test "registers channel events in connection history", %{conn: conn, chan: chan} do
    return_handler = self()
    assert ref = monitor_channel(chan)
    assert is_reference(ref)
    assert :ok = register_return_handler(chan, return_handler)
    assert :ok = qos(chan, prefetch_count: 10)
    assert :ok = ack(chan, "tag1", [])
    assert :ok = nack(chan, "tag2", requeue: false)
    assert :ok = reject(chan, "tag3", requeue: false)
    assert :ok = close_channel(chan)

    assert [
             {:open_channel, [^conn]},
             {:monitor_channel, [^chan]},
             {:register_return_handler, [^chan, ^return_handler]},
             {:qos, [^chan, [prefetch_count: 10]]},
             {:ack, [^chan, "tag1", []]},
             {:nack, [^chan, "tag2", [requeue: false]]},
             {:reject, [^chan, "tag3", [requeue: false]]},
             {:close_channel, [^chan]}
           ] = history(conn)
  end

  test "registers exchange events in connection history", %{conn: conn, chan: chan} do
    assert :ok = declare_exchange(chan, "topic-exchange", :topic, [])
    assert :ok = declare_exchange(chan, "fanout-exchange", :fanout, durable: true)
    assert :ok = bind_exchange(chan, "fanout-exchange", "topic-exchange", routing_key: "#")
    assert :ok = publish(chan, "topic-exchange", "key", "payload", durable: true)

    assert [
             {:open_channel, [^conn]},
             {:declare_exchange, [^chan, "topic-exchange", :topic, []]},
             {:declare_exchange, [^chan, "fanout-exchange", :fanout, [durable: true]]},
             {:bind_exchange, [^chan, "fanout-exchange", "topic-exchange", [routing_key: "#"]]},
             {:publish, [^chan, "topic-exchange", "key", "payload", [durable: true]]}
           ] = history(conn)
  end

  test "registers queue events in connection history", %{conn: conn, chan: chan} do
    assert {:ok, name} = declare_queue(chan, "", durable: true)
    assert :ok = bind_queue(chan, name, "topic-exchange", routing_key: "#")

    consumer = self()
    assert {:ok, tag} = consume(chan, name, consumer, [])

    assert [
             {:open_channel, [^conn]},
             {:declare_queue, [^chan, "", [durable: true]]},
             {:bind_queue, [^chan, ^name, "topic-exchange", [routing_key: "#"]]},
             {:consume, [^chan, ^name, ^consumer, ^tag, []]}
           ] = history(conn)
  end

  test "returns event by type if specified", %{conn: conn, chan: chan} do
    assert :ok = publish(chan, "exchange", "key1", "payload", [])
    assert :ok = publish(chan, "exchange", "key2", "payload", [])
    assert :ok = close_channel(chan)

    assert [
             {:publish, [^chan, "exchange", "key1", "payload", []]},
             {:publish, [^chan, "exchange", "key2", "payload", []]}
           ] = history(conn, :publish)

    assert history(conn) != history(conn, :publish)
  end
end
