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
      check all name <- identifier(),
                type <- member_of([:direct, :fanout, :topic]),
                durable? <- boolean(),
                auto_delete? <- boolean(),
                internal? <- boolean(),
                max_runs: 10 do
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
      check all name <- identifier(),
                durable? <- boolean(),
                auto_delete? <- boolean(),
                max_runs: 10 do
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

  defp identifier do
    string(:alphanumeric, min_length: 1) |> map(&("freddy_test." <> &1))
  end
end
