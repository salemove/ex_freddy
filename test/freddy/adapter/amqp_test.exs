defmodule Freddy.Adapter.AMQPTest do
  use ExUnit.Case
  use ExUnitProperties

  import Freddy.Adapter.AMQP

  setup do
    {:ok, freddy_conn} = open_connection([])
    {:ok, freddy_chan} = open_channel(freddy_conn)

    {:ok, amqp_conn} = AMQP.Connection.open()
    {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)

    {:ok, freddy: freddy_chan, amqp: amqp_chan}
  end

  describe "declare_exchange/4" do
    property "can declare an exchange", %{freddy: freddy, amqp: amqp} do
      check all(
              name <- identifier(),
              type <- member_of([:direct, :fanout, :topic]),
              durable? <- boolean(),
              auto_delete? <- boolean(),
              internal? <- boolean(),
              max_runs: 10
            ) do
        options = [
          durable: durable?,
          auto_delete: auto_delete?,
          internal: internal?
        ]

        assert :ok = declare_exchange(freddy, name, type, options)
        # check that exactly same exchange can be declared again with using different library
        assert :ok = AMQP.Exchange.declare(amqp, name, type, options)
        # remove artifact
        assert :ok = AMQP.Exchange.delete(amqp, name)
      end
    end
  end

  describe "declare_queue/3" do
    property "can declare a queue", %{freddy: freddy, amqp: amqp} do
      check all(
              name <- identifier(),
              durable? <- boolean(),
              auto_delete? <- boolean(),
              max_runs: 10
            ) do
        options = [
          durable: durable?,
          auto_delete: auto_delete?
        ]

        assert {:ok, ^name} = declare_queue(freddy, name, options)
        assert {:ok, %{queue: ^name}} = AMQP.Queue.declare(amqp, name, options)
        assert {:ok, _meta} = AMQP.Queue.delete(amqp, name)
      end
    end
  end

  describe "delete_queue/3" do
    property "can delete a queue", %{freddy: freddy, amqp: amqp} do
      check all(
              name <- identifier(),
              if_unused? <- boolean(),
              if_empty? <- boolean(),
              max_runs: 10
            ) do
        options = [
          if_unused: if_unused?,
          if_empty: if_empty?
        ]

        # With the check all property testing the setup block is only run once
        # The channel will get shutdown during this test so we need to ensure
        # it is started.
        amqp = ensure_amqp_channel(amqp)

        # Create the queue in different library
        assert {:ok, %{queue: ^name}} = AMQP.Queue.declare(amqp, name)
        # Ensure we can delete it
        assert {:ok, %{message_count: 0}} = delete_queue(freddy, name, options)
        # Catch the exit with a 404 that indicates the queue doesn't exist
        # and actually got deleted
        assert {{:shutdown, {:server_initiated_close, 404, _}}, _} =
                 catch_exit(AMQP.Queue.declare(amqp, name, passive: true))
      end
    end
  end

  defp identifier do
    string(:alphanumeric, min_length: 1) |> map(&("freddy_test." <> &1))
  end

  defp ensure_amqp_channel(amqp) do
    if Process.alive?(amqp.pid) do
      amqp
    else
      {:ok, amqp} = AMQP.Channel.open(amqp.conn)
      amqp
    end
  end
end
