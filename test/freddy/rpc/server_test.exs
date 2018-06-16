defmodule Freddy.RPC.ServerTest do
  use Freddy.ConnectionCase, async: true

  require Integer

  defmodule TestServer do
    use Freddy.RPC.Server

    @default_config [
      queue: [name: "freddy-test-rpc-queue"]
    ]

    def start_link(conn, config \\ @default_config, pid) do
      Freddy.RPC.Server.start_link(__MODULE__, conn, config, pid)
    end

    @impl true
    def init(initial) do
      case initial do
        :ignore -> :ignore
        :stop -> {:stop, :stopped}
        {pid, hooks} -> {:ok, {pid, Map.new(hooks)}}
        pid -> {:ok, {pid, %{}}}
      end
    end

    @impl true
    def handle_connected(meta, state) do
      case get_hook(state, :handle_connected, {:noreply, :_}) do
        {:noreply, state} ->
          notify(state, {:connected, meta})
          {:noreply, state}

        other ->
          other
      end
    end

    @impl true
    def handle_ready(meta, state) do
      notify(state, {:ready, meta})
      get_hook(state, :handle_ready, {:noreply, :_})
    end

    @impl true
    def handle_disconnected(reason, state) do
      notify(state, {:disconnected, reason})
      get_hook(state, :handle_disconnected, {:noreply, :_})
    end

    @impl true
    def decode_request(payload, meta, state) do
      notify(state, {:decode_request, payload, meta})
      get_hook(state, :decode_request, {:ok, payload, :_})
    end

    @impl true
    def handle_request(request, meta, state) do
      notify(state, {:handle_request, request, meta})
      get_hook(state, :handle_request, {:reply, request, :_})
    end

    @impl true
    def encode_response(payload, opts, state) do
      notify(state, {:encode_response, payload, opts})
      get_hook(state, :encode_response, {:reply, payload, :_})
    end

    @impl true
    def handle_call(request, _from, state) do
      {:reply, request, state}
    end

    @impl true
    def handle_cast(message, state) do
      notify(state, {:cast, message})
      {:noreply, state}
    end

    @impl true
    def handle_info(message, state) do
      notify(state, {:info, message})
      {:noreply, state}
    end

    @impl true
    def terminate(reason, state) do
      notify(state, {:terminate, reason})
    end

    defp get_hook({_pid, hooks} = state, hook, default) do
      hooks
      |> Map.get(hook, default)
      |> process_hook(state)
    end

    defp process_hook(hook, state) when is_tuple(hook) do
      hook
      |> Tuple.to_list()
      |> Enum.map(&if &1 == :_, do: state, else: &1)
      |> :erlang.list_to_tuple()
    end

    defp process_hook(hook, state) when is_function(hook, 0) do
      process_hook(hook.(), state)
    end

    defp notify({pid, _hooks}, message) do
      send(pid, message)
    end
  end

  describe "init/1" do
    test "doesn't start process if :ignore is returned", %{connection: conn} do
      assert :ignore = TestServer.start_link(conn, :ignore)
    end

    test "stops process if {:stop, reason} is returned", %{connection: conn} do
      Process.flag(:trap_exit, true)

      assert {:error, :stopped} = TestServer.start_link(conn, :stop)
      assert_receive {:EXIT, _pid, :stopped}
    end

    test "starts process if {:ok, state} is returned", %{connection: conn} do
      assert {:ok, pid} = TestServer.start_link(conn, self())
      assert is_pid(pid)
    end
  end

  describe "handle_connected/2" do
    test "called after server is set up with default config", %{connection: conn} do
      config = [queue: [name: "rpc-queue"]]
      {:ok, server} = TestServer.start_link(conn, config, self())

      assert_receive {:connected,
                      %{
                        channel: %{chan: chan},
                        queue: %{name: "rpc-queue"},
                        exchange: %{name: ""}
                      }}

      assert [
               {:declare_queue, [^chan, "rpc-queue", []]},
               {:qos, [^chan, qos_opts]},
               {:consume, [^chan, "rpc-queue", ^server, _tag, [no_ack: true]]}
             ] = history(conn, [:declare_queue, :declare_exchange, :qos, :bind_queue, :consume])

      assert Map.new(qos_opts) == %{global: false, prefetch_count: 0, prefetch_size: 0}
    end

    test "called after server is set up with custom config", %{connection: conn} do
      config = [
        queue: [
          name: "rpc-queue",
          opts: [
            durable: true,
            exclusive: false,
            passive: true
          ]
        ],
        exchange: [
          name: "rpc-exchange",
          type: :topic,
          opts: [
            durable: true,
            passive: true
          ]
        ],
        qos: [
          prefetch_count: 10
        ],
        consumer: [
          no_ack: false
        ],
        routing_keys: ["rpc.*", "_rpc.*"]
      ]

      {:ok, server} = TestServer.start_link(conn, config, self())

      assert_receive {:connected,
                      %{
                        channel: %{chan: chan},
                        queue: %{name: "rpc-queue"},
                        exchange: %{name: "rpc-exchange"}
                      }}

      assert [
               {:declare_exchange, [^chan, "rpc-exchange", :topic, [durable: true, passive: true]]},
               {:declare_queue,
                [^chan, "rpc-queue", [durable: true, exclusive: false, passive: true]]},
               {:qos, [^chan, qos_opts]},
               {:bind_queue, [^chan, "rpc-queue", "rpc-exchange", bind_opts1]},
               {:bind_queue, [^chan, "rpc-queue", "rpc-exchange", bind_opts2]},
               {:consume, [^chan, "rpc-queue", ^server, _tag, [no_ack: false]]}
             ] = history(conn, [:declare_queue, :declare_exchange, :qos, :bind_queue, :consume])

      assert Map.new(qos_opts) == %{global: false, prefetch_count: 10, prefetch_size: 0}
      assert bind_opts1[:routing_key] == "rpc.*"
      assert bind_opts2[:routing_key] == "_rpc.*"
    end

    test "stops process if returning {:stop, reason, state}", %{connection: conn} do
      Process.flag(:trap_exit, true)

      {:ok, server} =
        TestServer.start_link(conn, {self(), [handle_connected: {:stop, :stopped, :_}]})

      assert_receive {:EXIT, ^server, :stopped}
    end

    test "re-establishes consumer if returning {:error, state}", %{connection: conn} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      handle_connected = fn ->
        if Integer.is_even(Agent.get_and_update(counter, &{&1, &1 + 1})) do
          {:error, :_}
        else
          {:noreply, :_}
        end
      end

      {:ok, server} = TestServer.start_link(conn, {self(), [handle_connected: handle_connected]})
      assert_receive {:connected, _}

      assert [
               {:open_channel, [conn_pid]},
               {:consume, [chan1, "freddy-test-rpc-queue", ^server, _, opts]},
               {:open_channel, [conn_pid]},
               {:consume, [chan2, "freddy-test-rpc-queue", ^server, _, opts]}
             ] = history(conn, [:open_channel, :consume])

      assert chan1 != chan2
    end
  end

  describe "handle_ready/2" do
    test "called after broker confirms successful consumer setup", %{connection: conn} do
      {:ok, server} = TestServer.start_link(conn, self())
      assert_receive {:connected, _}
      refute_receive {:ready, _}

      send(server, {:consume_ok, %{}})
      assert_receive {:ready, %{}}
    end

    test "stops process if returning {:stop, reason, state}", %{connection: conn} do
      Process.flag(:trap_exit, true)

      {:ok, server} = TestServer.start_link(conn, {self(), [handle_ready: {:stop, :stopped, :_}]})
      assert_receive {:connected, _}

      send(server, {:consume_ok, %{}})
      assert_receive {:EXIT, ^server, :stopped}
    end
  end

  describe "handle_disconnected/2" do
    test "reconnects after connected channel has been closed", %{connection: conn} do
      assert {:ok, _pid} = TestServer.start_link(conn, self())
      assert_receive {:connected, %{channel: chan}}

      Freddy.Core.Channel.close(chan)

      assert_receive {:disconnected, :normal}
      assert_receive {:connected, _}
    end

    test "stops process if {:stop, reason, state} is returned", %{connection: conn} do
      Process.flag(:trap_exit, true)

      assert {:ok, server} =
               TestServer.start_link(conn, {self(), [handle_disconnected: {:stop, :stopped, :_}]})

      assert_receive {:connected, %{channel: chan}}

      Freddy.Core.Channel.close(chan)

      assert_receive {:disconnected, :normal}
      assert_receive {:EXIT, ^server, :stopped}
    end
  end

  describe "decode_request/3, handle_request/3, encode_response/3" do
    setup %{connection: conn} = context do
      {:ok, server} = TestServer.start_link(conn, {self(), context[:hooks] || []})
      send(server, {:consume_ok, %{}})

      {:ok, Map.put(context, :server, server)}
    end

    for callback <- ~w[decode_request handle_request encode_response]a do
      @tag hooks: [{callback, {:stop, :stopped, :_}}]
      test "stops process if #{callback}/3 returns {:stop, reason, state}", context do
        Process.flag(:trap_exit, true)

        send_request(context, "request")
        assert_receive {:EXIT, _, :stopped}
      end

      @tag hooks: [{callback, {:noreply, :_}}]
      test "ignores request if #{callback}/3 returns {:noreply, state}", context do
        request = send_request(context, "request")
        refute_responded(request)
      end
    end

    @tag hooks: [decode_request: {:reply, "response", :_}]
    test "publishes encoded response immediately if decode_request/3 returns {:reply, response, state}",
         context do
      request = send_request(context, "request")

      assert_receive {:decode_request, "request", _}
      assert_receive {:encode_response, "response", _}

      assert_responded(request, "response")
    end

    @tag hooks: [decode_request: {:reply, "response", [app: "test"], :_}]
    test "publishes encoded response with custom options immediately " <>
           "if decode_request/3 returns {:reply, response, opts, state}",
         context do
      request = send_request(context, "request")

      assert_receive {:decode_request, "request", _}
      assert_receive {:encode_response, "response", _}

      assert_responded(request, "response", app: "test")
    end

    @tag hooks: [handle_request: {:reply, "response", :_}]
    test "publishes encoded response if handle_request/3 returns {:reply, response, state}",
         context do
      request = send_request(context, "request")

      assert_receive {:decode_request, "request", _}
      assert_receive {:handle_request, "request", _}
      assert_receive {:encode_response, "response", _}

      assert_responded(request, "response")
    end

    @tag hooks: [handle_request: {:noreply, :_}]
    test "reply/2 publishes response given request meta", context do
      request = send_request(context, "request")

      assert_receive {:handle_request, "request", meta}
      Freddy.RPC.Server.reply(meta, "async response")

      assert_responded(request, "async response")
    end

    @tag hooks: [handle_request: {:reply, "response", [app: "test"], :_}]
    test "publishes encoded response with custom options " <>
           "if handle_request/3 returns {:reply, response, opts, state}",
         context do
      request = send_request(context, "request")

      assert_receive {:decode_request, "request", _}
      assert_receive {:handle_request, "request", _}
      assert_receive {:encode_response, "response", _}

      assert_responded(request, "response", app: "test")
    end

    @tag hooks: [encode_response: {:reply, "response", :_}]
    test "publishes encoded response if encode_response/3 returns {:reply, response, state}",
         context do
      request = send_request(context, "request")

      assert_receive {:decode_request, "request", _}
      assert_receive {:handle_request, "request", _}
      assert_receive {:encode_response, "request", _}

      assert_responded(request, "response")
    end

    @tag hooks: [encode_response: {:reply, "response", [app: "test"], :_}]
    test "publishes encoded response with custom options " <>
           "if encode_response/3 returns {:reply, response, opts, state}",
         context do
      request = send_request(context, "request")

      assert_receive {:decode_request, "request", _}
      assert_receive {:handle_request, "request", _}
      assert_receive {:encode_response, "request", _}

      assert_responded(request, "response", app: "test")
    end

    test "doesn't publish response if request is missing :reply_to or :correlation_id", context do
      send(context.server, {:deliver, "request1", %{correlation_id: "correlation_id"}})
      send(context.server, {:deliver, "request2", %{reply_to: "reply-queue"}})
      send(context.server, {:deliver, "request3", %{}})

      assert_receive {:handle_request, "request1", _}
      assert_receive {:handle_request, "request2", _}
      assert_receive {:handle_request, "request3", _}

      refute_receive {:encode_response, _, _}
      refute_responded(context)
    end

    defp send_request(%{connection: conn, server: server}, payload) do
      meta = %{reply_to: "reply-queue", correlation_id: "correlation_id"}
      send(server, {:deliver, payload, meta})

      meta
      |> Map.put(:server, server)
      |> Map.put(:connection, conn)
    end

    defp assert_responded(
           %{connection: conn, server: server, reply_to: reply_to, correlation_id: correlation_id},
           response,
           opts \\ []
         ) do
      # synchronize state
      _ = :sys.get_state(server)

      assert [publish: [_chan, "", ^reply_to, ^response, received_opts]] = history(conn, :publish)
      assert received_opts[:correlation_id] == correlation_id

      for {opt, value} <- opts do
        assert received_opts[opt] == value
      end
    end

    defp refute_responded(%{connection: conn, server: server}) do
      # synchronize state
      _ = :sys.get_state(server)
      assert [] = history(conn, :publish)
    end
  end

  describe "handle_call/3" do
    test "replies to requester", %{connection: conn} do
      {:ok, server} = TestServer.start_link(conn, self())
      assert :ping = Freddy.RPC.Server.call(server, :ping)
    end
  end

  describe "handle_cast/2" do
    test "called on GenServer.cast", %{connection: conn} do
      {:ok, server} = TestServer.start_link(conn, self())
      Freddy.RPC.Server.cast(server, :message)
      assert_receive {:cast, :message}
    end
  end

  describe "handle_info/2" do
    test "called on arbitrary message", %{connection: conn} do
      {:ok, server} = TestServer.start_link(conn, self())
      send(server, :message)
      assert_receive {:info, :message}
    end
  end

  describe "terminate/2" do
    test "called when server is stopped", %{connection: conn} do
      {:ok, server} = TestServer.start_link(conn, self())
      Freddy.RPC.Server.stop(server, :normal)
      assert_receive {:terminate, :normal}

      refute Process.alive?(server)
    end
  end
end
