defmodule Freddy.Core.ActorTest do
  use ExUnit.Case, async: true

  defmodule ConnectionSlowProxy do
    # proxies calls to Freddy.Connection, but adds a delay before
    # opening a channel first time

    use GenServer

    def start_link(initial_delay) do
      GenServer.start_link(__MODULE__, initial_delay)
    end

    def init(initial_delay) do
      {:ok, connection} = Freddy.Connection.start_link(adapter: :sandbox)
      {:ok, %{connection: connection, delay: initial_delay}}
    end

    def handle_call(:open_channel, _from, %{connection: connection, delay: delay}) do
      Process.sleep(delay)
      {:reply, Freddy.Connection.open_channel(connection), %{connection: connection, delay: 0}}
    end
  end

  defmodule TestActor do
    @behaviour Freddy.Core.Actor

    def start_link(connection) do
      Freddy.Core.Actor.start_link(__MODULE__, connection, false)
    end

    def connected?(actor) do
      GenServer.call(actor, :get)
    end

    def init(connected?) do
      {:ok, connected?}
    end

    def handle_connected(_meta, _connected?) do
      {:noreply, true}
    end

    def handle_disconnected(_reason, _connected?) do
      {:noreply, false}
    end

    def handle_call(:get, _from, connected?) do
      {:reply, connected?, connected?}
    end

    def handle_cast(_message, state) do
      {:noreply, state}
    end

    def handle_info(_message, state) do
      {:noreply, state}
    end

    def terminate(_reason, _state) do
      :ok
    end
  end

  test "retries if channel couldn't be opened" do
    {:ok, conn} = ConnectionSlowProxy.start_link(5000)
    {:ok, actor} = TestActor.start_link(conn)

    refute TestActor.connected?(actor)
    Process.sleep(5000)
    assert TestActor.connected?(actor)
  end
end
