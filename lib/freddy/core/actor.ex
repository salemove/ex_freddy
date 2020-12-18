defmodule Freddy.Core.Actor do
  @moduledoc false

  @type state :: term
  @type reason :: term
  @type reply :: term
  @type meta :: %{channel: Freddy.Core.Channel.t()}

  @callback init(args :: term) ::
              {:ok, state}
              | :ignore
              | {:stop, reason}

  @callback handle_connected(meta, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:error, state}
              | {:stop, reason, state}

  @callback handle_disconnected(reason, state) ::
              {:noreply, state}
              | {:stop, reason, state}

  @callback handle_call(request :: term, GenServer.from(), state) ::
              {:reply, reply, state}
              | {:reply, reply, state, timeout | :hibernate}
              | {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason, reply, state}
              | {:stop, reason, state}

  @callback handle_cast(request :: term, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason, state}

  @callback handle_info(message :: :timeout | term, state) ::
              {:noreply, state}
              | {:noreply, state, timeout | :hibernate}
              | {:stop, reason, state}

  @callback terminate(reason, state) :: term

  defmacro __using__(state_extra_keys \\ []) do
    state_keys = [mod: nil, config: [], given: nil, channel: nil] ++ state_extra_keys

    quote location: :keep do
      @behaviour unquote(__MODULE__)

      @type payload :: term
      @type meta :: map
      @type state :: term
      @type connection :: GenServer.server()
      @type consumer_options :: [{:channel_open_timeout, timeout()}]

      @doc """
      Called when the `#{Macro.to_string(__MODULE__)}` process is first started.

      Returning `{:ok, state}` will cause `start_link/3` to return `{:ok, pid}` and attempt to
      open a channel on the given connection and initialize an actor (it depends on the actor's
      nature, consumer will, for example, declare an exchange, a queue and a bindings).

      After that it will enter the main loop with `state` as its internal state.

      Returning `:ignore` will cause `start_link/3` to return `:ignore` and the
      process will exit normally without entering the loop, opening a channel or calling
      `c:terminate/2`.

      Returning `{:stop, reason}` will cause `start_link/3` to return `{:error, reason}` and
      the process will exit with reason `reason` without entering the loop, opening a channel,
      or calling `c:terminate/2`.
      """
      @callback init(state) ::
                  {:ok, state}
                  | {:ok, state, consumer_options}
                  | :ignore
                  | {:stop, reason :: term}

      @doc """
      Called when the `#{Macro.to_string(__MODULE__)}` process has been disconnected from the AMQP broker.

      Returning `{:noreply, state}` causes the process to enter the main loop with
      the given state. The process will not consume any new messages until connection
      to AMQP broker is established again.

      Returning `{:stop, reason, state}` will terminate the main loop and call
      `c:terminate/2` before the process exits with reason `reason`.
      """
      @callback handle_disconnected(reason :: term, state) ::
                  {:noreply, state}
                  | {:stop, reason :: term, state}

      @doc """
      Called when the process receives a call message sent by `call/3`. This
      callback has the same arguments as the `GenServer` equivalent and the
      `:reply`, `:noreply` and `:stop` return tuples behave the same.
      """
      @callback handle_call(request :: term, GenServer.from(), state) ::
                  {:reply, reply :: term, state}
                  | {:reply, reply :: term, state, timeout | :hibernate}
                  | {:noreply, state}
                  | {:noreply, state, timeout | :hibernate}
                  | {:stop, reason :: term, state}
                  | {:stop, reason :: term, reply :: term, state}

      @doc """
      Called when the process receives a cast message sent by `cast/2`. This
      callback has the same arguments as the `GenServer` equivalent and the
      `:noreply` and `:stop` return tuples behave the same.
      """
      @callback handle_cast(request :: term, state) ::
                  {:noreply, state}
                  | {:noreply, state, timeout | :hibernate}
                  | {:stop, reason :: term, state}

      @doc """
      Called when the process receives a message. This callback has the same
      arguments as the `GenServer` equivalent and the `:noreply` and `:stop`
      return tuples behave the same.
      """
      @callback handle_info(term, state) ::
                  {:noreply, state}
                  | {:noreply, state, timeout | :hibernate}
                  | {:stop, reason :: term, state}

      @doc """
      This callback is the same as the `GenServer` equivalent and is called when the
      process terminates. The first argument is the reason the process is about
      to exit with.
      """
      @callback terminate(reason :: term, state) :: any

      import Record

      defrecordp :state, unquote(state_keys)

      @doc """
      Start a `#{Macro.to_string(__MODULE__)}` process linked to the current process.

      Arguments:

        * `mod` - the module that defines the server callbacks (like `GenServer`)
        * `connection` - the pid of a `Freddy.Connection` process
        * `config` - the configuration of the consumer
        * `initial` - the value that will be given to `c:init/1`
        * `opts` - the GenServer options
      """
      @spec start_link(module, connection, Keyword.t(), initial :: term, GenServer.options()) ::
              GenServer.on_start()
      def start_link(mod, connection, config, initial, opts \\ []) do
        Freddy.Core.Actor.start_link(__MODULE__, connection, {mod, config, initial}, opts)
      end

      @doc """
      Start a `#{Macro.to_string(__MODULE__)}` process without linking to the current process.

      See `start_link/5` for more information.
      """
      def start(mod, connection, config, initial, opts \\ []) do
        Freddy.Core.Actor.start(__MODULE__, connection, {mod, config, initial}, opts)
      end

      defdelegate call(consumer, message, timeout \\ 5000), to: Connection
      defdelegate cast(consumer, message), to: Connection
      defdelegate stop(consumer, reason \\ :normal), to: GenServer

      @impl true
      def init({mod, config, initial}) do
        case mod.init(initial) do
          {:ok, given} -> {:ok, state(mod: mod, config: config, given: given)}
          ignore_or_stop -> ignore_or_stop
        end
      end

      @impl true
      def handle_disconnected(reason, state(mod: mod, given: given) = state) do
        case mod.handle_disconnected(reason, given) do
          {:noreply, new_given} -> {:noreply, state(state, given: new_given)}
          {:stop, reason, new_given} -> {:stop, reason, state(state, given: new_given)}
        end
      end

      @impl true
      def handle_call(message, from, state(mod: mod, given: given) = state) do
        case mod.handle_call(message, from, given) do
          {:reply, reply, new_given} ->
            {:reply, reply, state(state, given: new_given)}

          {:reply, reply, new_given, timeout} ->
            {:reply, reply, state(state, given: new_given), timeout}

          {:noreply, new_given} ->
            {:noreply, state(state, given: new_given)}

          {:noreply, new_given, timeout} ->
            {:noreply, state(state, given: new_given), timeout}

          {:stop, reason, new_given} ->
            {:stop, reason, state(state, given: new_given)}

          {:stop, reason, reply, new_given} ->
            {:stop, reason, reply, state(state, given: new_given)}
        end
      end

      @impl true
      def handle_cast(message, state(mod: mod, given: given) = state) do
        message
        |> mod.handle_cast(given)
        |> handle_async_result(state)
      end

      @impl true
      def handle_info(message, state(mod: mod, given: given) = state) do
        message
        |> mod.handle_info(given)
        |> handle_async_result(state)
      end

      @impl true
      def terminate(reason, state(mod: mod, given: given)) do
        mod.terminate(reason, given)
      end

      defp handle_async_result(result, state) do
        case result do
          {:noreply, new_given} -> {:noreply, state(state, given: new_given)}
          {:noreply, new_given, timeout} -> {:noreply, state(state, given: new_given), timeout}
          {:stop, reason, new_given} -> {:stop, reason, state(state, given: new_given)}
        end
      end

      defp handle_mod_connected(meta, state(mod: mod, given: given) = state) do
        case mod.handle_connected(meta, given) do
          {:noreply, new_given} ->
            {:noreply, state(state, given: new_given)}

          {:noreply, new_given, timeout} ->
            {:noreply, state(state, given: new_given), timeout}

          {:error, new_given} ->
            {:error, state(state, given: new_given)}

          {:stop, reason, new_given} ->
            {:stop, reason, state(state, given: new_given)}
        end
      end

      defoverridable handle_disconnected: 2,
                     handle_info: 2,
                     handle_cast: 2,
                     handle_call: 3,
                     terminate: 2
    end
  end

  use Connection

  alias Freddy.Core.Channel

  @reconnection_interval 1000
  @default_channel_open_timeout 3000

  @doc false
  def start_link(mod, connection, initial, opts \\ []) do
    Connection.start_link(__MODULE__, {mod, connection, initial}, opts)
  end

  @doc false
  def start(mod, connection, initial, opts \\ []) do
    Connection.start(__MODULE__, {mod, connection, initial}, opts)
  end

  @impl true
  def init({mod, connection, initial}) do
    case mod.init(initial) do
      {:ok, given} ->
        do_after_init(mod, connection, given, [])

      {:ok, given, options} ->
        do_after_init(mod, connection, given, options)

      :ignore ->
        :ignore

      {:stop, reason} ->
        {:stop, reason}
    end
  end


  @impl true
  def connect(_info, %{connection: connection,
                       channel_ref: nil,
                       channel_open_timeout: channel_open_timeout} = state) do
    case Freddy.Connection.open_channel(connection, channel_open_timeout) do
      {:ok, channel} ->
        bind_to_channel(channel, state)

      _error ->
        {:backoff, @reconnection_interval, state}
    end
  catch
    :exit, {:timeout, _} ->
      {:backoff, @reconnection_interval, state}
  end

  @impl true
  def connect(_info, state) do
    {:ok, state}
  end

  @impl true
  def disconnect(_info, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_call(message, from, %{mod: mod, given: given} = state) do
    case mod.handle_call(message, from, given) do
      {:reply, reply, new_given} ->
        {:reply, reply, %{state | given: new_given}}

      {:reply, reply, new_given, timeout} ->
        {:reply, reply, %{state | given: new_given}, timeout}

      {:noreply, new_given} ->
        {:noreply, %{state | given: new_given}}

      {:noreply, new_given, timeout} ->
        {:noreply, %{state | given: new_given}, timeout}

      {:stop, reason, reply, new_given} ->
        {:stop, reason, reply, %{state | given: new_given}}

      {:stop, reason, new_given} ->
        {:stop, reason, %{state | given: new_given}}
    end
  end

  @impl true
  def handle_cast(message, %{mod: mod, given: given} = state) do
    case mod.handle_cast(message, given) do
      {:noreply, new_given} ->
        {:noreply, %{state | given: new_given}}

      {:noreply, new_given, timeout} ->
        {:noreply, %{state | given: new_given}, timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, %{state | given: new_given}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, reason}, %{connection_ref: ref} = state) do
    {:stop, reason, state}
  end

  def handle_info({:DOWN, ref, _, _, reason}, %{channel_ref: ref, mod: mod, given: given} = state) do
    new_state = %{state | channel: nil, channel_ref: nil}

    case mod.handle_disconnected(reason, given) do
      {:noreply, new_given} -> {:connect, :reconnect, %{new_state | given: new_given}}
      {:stop, reason, new_given} -> {:stop, reason, %{new_state | given: new_given}}
    end
  end

  def handle_info({ref, {:ok, %Channel{} = channel}}, state) when is_reference(ref) do
    case handle_out_of_context_channel(channel, state) do
      {:ok, state} ->
        {:noreply, state}

      {:stop, reason, state} ->
        {:stop, reason, state}

      {:backoff, _, _} = res ->
        res
    end
  end

  def handle_info(message, %{mod: mod, given: given} = state) do
    case mod.handle_info(message, given) do
      {:noreply, new_given} ->
        {:noreply, %{state | given: new_given}}

      {:noreply, new_given, timeout} ->
        {:noreply, %{state | given: new_given}, timeout}

      {:stop, reason, new_given} ->
        {:stop, reason, %{state | given: new_given}}
    end
  end

  @impl true
  def terminate(reason, %{mod: mod, given: given} = _state) do
    mod.terminate(reason, given)
  end

  defp do_after_init(mod, connection, given, options) do
    ref = Process.monitor(connection)

    channel_open_timeout =
      Keyword.get(options, :channel_open_timeout, @default_channel_open_timeout)

    {:connect, :connect,
     %{
       channel_open_timeout: channel_open_timeout,
       mod: mod,
       connection: connection,
       connection_ref: ref,
       given: given,
       channel: nil,
       channel_ref: nil
     }}
  end

  defp bind_to_channel(channel, state) do
    ref = Channel.monitor(channel)

    state
    |> Map.put(:channel, channel)
    |> Map.put(:channel_ref, ref)
    |> handle_mod_connected()
  end

  defp handle_out_of_context_channel(channel, %{channel: nil} = state) do
    bind_to_channel(channel, state)
  end

  defp handle_out_of_context_channel(channel, state) do
    Channel.close(channel)
    {:ok, state}
  end

  defp handle_mod_connected(%{mod: mod, channel: channel, channel_ref: ref, given: given} = state) do
    case mod.handle_connected(%{channel: channel}, given) do
      {:noreply, new_given} ->
        {:ok, %{state | given: new_given}}

      {:noreply, new_given, timeout} ->
        {:ok, %{state | given: new_given}, timeout}

      {:error, new_given} ->
        Process.demonitor(ref, [:flush])
        Channel.close(channel)
        connect(:reconnect, %{state | channel: nil, channel_ref: nil, given: new_given})

      {:stop, reason, new_given} ->
        {:stop, reason, %{state | given: new_given}}
    end
  end
end
