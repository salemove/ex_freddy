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
          routing_key: routing_key,
          payload: payload,
          start_time: time,
          stop_time: time | nil,
          options: options,
          meta: map
        }

  @typedoc "Request identifier. Used only internally, can be anything"
  @type id :: term

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
            routing_key: "",
            payload: nil,
            start_time: nil,
            stop_time: nil,
            options: [],
            meta: %{}

  @spec start(id, payload, routing_key, options) :: t
  def start(id, payload, routing_key, options) do
    %Request{
      id: id,
      routing_key: routing_key,
      payload: payload,
      options: options,
      start_time: now()
    }
  end

  @spec finish(t) :: t
  def finish(%Request{} = req),
    do: %{req | stop_time: now()}

  @spec duration(t, granularity :: System.time_unit()) :: integer
  def duration(%Request{start_time: t1, stop_time: t2} = _req, granularity \\ :milliseconds)
      when is_integer(t2),
      do: System.convert_time_unit(t2 - t1, :native, granularity)

  @spec update_routing_key(t, routing_key) :: t
  def update_routing_key(%Request{} = req, new_routing_key),
    do: %{req | routing_key: new_routing_key}

  @spec update_payload(t, payload) :: t
  def update_payload(%Request{} = req, new_payload),
    do: %{req | payload: new_payload}

  @spec put_option(t, option :: atom, value :: term) :: t
  def put_option(%Request{options: options} = req, option, value),
    do: %{req | options: Keyword.put(options, option, value)}

  @spec put_meta(t, key :: term, value :: term) :: t
  def put_meta(%Request{meta: meta} = req, key, value),
    do: %{req | meta: Map.put(meta, key, value)}

  defp now(), do: System.monotonic_time()
end
