defmodule Freddy.QoS do
  @moduledoc """
  Channel QoS configuration
  """

  defstruct prefetch_count: 0, prefetch_size: 0, global: false

  def new(%__MODULE__{} = qos) do
    qos
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  def default do
    %__MODULE__{}
  end

  def declare(%__MODULE__{} = qos, channel) do
    opts =
      qos
      |> Map.from_struct()
      |> Keyword.new()

    try do
      AMQP.Basic.qos(channel, opts)
    rescue
      MatchError ->
        {:error, :qos_error}
    end
  end
end
