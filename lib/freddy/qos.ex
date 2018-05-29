defmodule Freddy.QoS do
  @moduledoc """
  Channel QoS configuration
  """

  use Freddy.AMQP, prefetch_count: 0, prefetch_size: 0, global: false

  def default do
    %__MODULE__{}
  end

  def declare(%__MODULE__{} = qos, channel) do
    opts =
      qos
      |> Map.from_struct()
      |> Keyword.new()

    safe_amqp(on_error: {:error, :qos_error}) do
      AMQP.Basic.qos(channel, opts)
    end
  end
end
