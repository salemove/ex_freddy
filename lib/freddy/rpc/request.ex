defmodule Freddy.RPC.Request do
  @moduledoc ~S"""
  RPC Request data structure. Applications may modify this data structure.
  For example, one might want to add some specific publication option to
  every request, or change routing key, based on request payload, or just
  add some application-specific meta-information.

  ## Examples

  Partial implementation of `Freddy.RPC.Client` behaviour:

      alias Freddy.RPC.Request

      def before_request(request, state) do
        new_request =
          request
          |> Request.put_option(:priority, 9)
          |> Request.put_option(:user_id, Application.get_env(:my_app, :rabbitmq)[:user_id])
          |> Request.update_payload(fn %{} = payload -> Map.put(payload, :now, DateTime.utc_now())

        {:ok, new_request, state}
      end

      def on_response(response, request, state) do
        Logger.info("Request #{request.id} is completed in #{Request.duration(request)} ms")

        {:reply, response, state}
      end
  """

  alias __MODULE__

  @type t :: %__MODULE__{
          id: id,
          from: from,
          routing_key: routing_key,
          payload: payload,
          start_time: time,
          stop_time: time | nil,
          options: options,
          meta: map,
          timer: timer
        }

  @typedoc """
  Request identifier, unique for every request.

  Applications SHOULD NOT change the generated identifier, but MAY use
  its value, for example, for logging purposes.
  """
  @type id :: String.t()

  @typedoc """
  Request routing key.

  Applications MAY modify request routing key using functions
  `set_routing_key/2` and `update_routing_key/2`.
  """
  @type routing_key :: String.t()

  @typedoc """
  Request options.

  Applications MAY read and modify request options using functions `put_option/3`,
  `get_option/3` and `remove_option/2`. Applications SHOULD NOT modify this
  field directly.

  See `AMQP.Basic.publish/5` for available options.
  """
  @type options :: Keyword.t()

  @typedoc """
  Request payload.

  Can be of any type initially. Applications MUST encode this field to a string (binary)
  before sending the message to server.
  """
  @type payload :: term

  @typedoc """
  Request meta information.

  Applications MAY read and modify meta-information using functions `put_meta/3`,
  `get_meta/3` and `remove_meta/2`. Applications SHOULD NOT modify this field
  directly.
  """
  @type meta :: map

  @typep from :: GenServer.from()
  @typep time :: integer
  @typep timer :: reference | nil

  defstruct id: nil,
            from: nil,
            routing_key: "",
            payload: nil,
            start_time: nil,
            stop_time: nil,
            options: [],
            timer: nil,
            meta: %{}

  @doc false
  @spec start(from, payload, routing_key, options) :: t
  def start(from, payload, routing_key, options) do
    %Request{
      id: generate_id(),
      from: from,
      routing_key: routing_key,
      payload: payload,
      options: options,
      start_time: now()
    }
  end

  @doc false
  @spec finish(t) :: t
  def finish(%Request{} = req) do
    %{req | stop_time: now()}
  end

  @doc """
  Get duration of the finished request with the given granularity.
  """
  @spec duration(t, granularity :: System.time_unit()) :: integer
  def duration(%Request{start_time: t1, stop_time: t2} = _request, granularity \\ :milliseconds)
      when is_integer(t2) do
    System.convert_time_unit(t2 - t1, :native, granularity)
  end

  @doc """
  Change request routing key to `new_routing_key`.
  """
  @spec set_routing_key(t, routing_key) :: t
  def set_routing_key(%Request{} = request, new_routing_key) when is_binary(new_routing_key) do
    %{request | routing_key: new_routing_key}
  end

  @doc """
  Update request routing key with the given function.
  """
  @spec update_routing_key(t, (routing_key -> routing_key)) :: t
  def update_routing_key(%Request{routing_key: key} = request, fun) when is_function(fun, 1) do
    %{request | routing_key: fun.(key)}
  end

  @doc """
  Change request payload to `new_payload`.
  """
  @spec set_payload(t, payload) :: t
  def set_payload(%Request{} = request, new_payload) do
    %{request | payload: new_payload}
  end

  @doc """
  Update request payload with the given function.
  """
  @spec update_payload(t, (payload -> payload)) :: t
  def update_payload(%Request{payload: payload} = request, fun) when is_function(fun, 1) do
    %{request | payload: fun.(payload)}
  end

  @doc """
  Add or change existing `option` of the request.
  """
  @spec put_option(t, option :: atom, value :: term) :: t
  def put_option(%Request{options: options} = request, option, value) do
    %{request | options: Keyword.put(options, option, value)}
  end

  @doc """
  Get value of the existing `option` of the request. If option is not set,
  the `default` value is returned.
  """
  @spec get_option(t, option :: atom, default :: term) :: t
  def get_option(%Request{options: options}, option, default \\ nil) do
    Keyword.get(options, option, default)
  end

  @doc """
  Removes the existing `option` from the request. If the option wasn't set,
  this action won't have any effect.
  """
  @spec remove_option(t, option :: atom) :: t
  def remove_option(%Request{options: options} = req, option) do
    %{req | options: Keyword.delete(options, option)}
  end

  @doc """
  Add arbitrary meta information with given `key` and `value` to the request.
  This information is not used by `Freddy` itself, but can be used by customized
  clients or servers to carry some additional information throughout the request
  lifecycle.
  """
  @spec put_meta(t, key :: term, value :: term) :: t
  def put_meta(%Request{meta: meta} = request, key, value) do
    %{request | meta: Map.put(meta, key, value)}
  end

  @doc """
  Get a value with the given `key` from the request meta-information dictionary.
  If the `key` is not set, the `default` value will be returned.
  """
  @spec get_meta(t, key :: term, default :: term) :: term
  def get_meta(%Request{meta: meta} = _request, key, default \\ nil) do
    Map.get(meta, key, default)
  end

  @doc """
  Remove the existing `key` from the request meta-information. If the key wasn't set,
  this action won't have any effect.
  """
  @spec remove_meta(t, key :: term) :: t
  def remove_meta(%Request{meta: meta} = request, key) do
    %{request | meta: Map.delete(meta, key)}
  end

  @doc """
  Change request timeout value. The timeout value can be given as a positive integer,
  or an `:infinity` atom. This value will be used by the RPC client to notify requester,
  that the server hasn't responded within a given `timeout` milliseconds interval.
  """
  @spec set_timeout(t, timeout) :: t
  def set_timeout(req, timeout)

  def set_timeout(%Request{} = req, :infinity) do
    remove_option(req, :expiration)
  end

  def set_timeout(%Request{} = req, timeout) do
    put_option(req, :expiration, to_string(timeout))
  end

  @doc """
  Get timeout value of the request.
  """
  @spec get_timeout(t) :: timeout
  def get_timeout(%Request{options: options} = _req) do
    case Keyword.get(options, :expiration, :infinity) do
      :infinity -> :infinity
      timeout -> String.to_integer(timeout)
    end
  end

  defp now(), do: System.monotonic_time()

  # Borrowed from Plug.RequestId
  defp generate_id do
    binary = <<
      System.system_time(:nanoseconds)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.hex_encode32(binary, case: :lower)
  end
end
