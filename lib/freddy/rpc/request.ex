defmodule Freddy.RPC.Request do
  @moduledoc """
  RPC Request data structure. Applications may modify this data structure.
  For example, one might want to add some specific publication option to
  every request, or change routing key, based on request payload, or just
  add some application-specific meta-information.
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
          timer: reference | nil
        }

  @typedoc "Request identifier. Used only internally, can be anything"
  @type id :: term

  @typedoc "Requester identifier provided by GenServer"
  @type from :: GenServer.from()

  @typedoc "Request routing key"
  @type routing_key :: binary

  @typedoc "Request options"
  @type options :: Keyword.t()

  @typedoc "Request payload"
  @type payload :: term

  @typedoc "Request meta information. Application can put their specific data here"
  @type meta :: map

  @type time :: integer

  defstruct id: nil,
            from: nil,
            routing_key: "",
            payload: nil,
            start_time: nil,
            stop_time: nil,
            options: [],
            timer: nil,
            meta: %{}

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

  @spec finish(t) :: t
  def finish(%Request{} = req) do
    %{req | stop_time: now()}
  end

  @spec duration(t, granularity :: System.time_unit()) :: integer
  def duration(%Request{start_time: t1, stop_time: t2} = _req, granularity \\ :milliseconds)
      when is_integer(t2) do
    System.convert_time_unit(t2 - t1, :native, granularity)
  end

  @spec update_routing_key(t, routing_key) :: t
  def update_routing_key(%Request{} = req, new_routing_key) do
    %{req | routing_key: new_routing_key}
  end

  @spec update_payload(t, payload) :: t
  def update_payload(%Request{} = req, new_payload) do
    %{req | payload: new_payload}
  end

  @spec put_option(t, option :: atom, value :: term) :: t
  def put_option(%Request{options: options} = req, option, value) do
    %{req | options: Keyword.put(options, option, value)}
  end

  @spec get_option(t, option :: atom, default :: term) :: t
  def get_option(%Request{options: options}, option, default \\ nil) do
    Keyword.get(options, option, default)
  end

  @spec remove_option(t, option :: atom) :: t
  def remove_option(%Request{options: options} = req, option) do
    %{req | options: Keyword.delete(options, option)}
  end

  @spec put_meta(t, key :: term, value :: term) :: t
  def put_meta(%Request{meta: meta} = req, key, value) do
    %{req | meta: Map.put(meta, key, value)}
  end

  @spec set_timeout(t, timeout) :: t
  def set_timeout(req, timeout)

  def set_timeout(%Request{} = req, :infinity) do
    remove_option(req, :expiration)
  end

  def set_timeout(%Request{} = req, timeout) do
    put_option(req, :expiration, to_string(timeout))
  end

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
