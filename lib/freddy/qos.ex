defmodule Freddy.QoS do
  @moduledoc """
  Channel quality of service configuration

  ## Fields

    * `:prefetch_size` - The client can request that messages be sent in
      advance so that when the client finishes processing a message, the
      following message is already held locally, rather than needing to
      be sent down the channel. Prefetching gives a performance improvement.
      This field specifies the prefetch window size in octets. The server
      will send a message in advance if it is equal to or smaller in size
      than the available prefetch size (and also falls into other prefetch
      limits). May be set to zero, meaning "no specific limit", although
      other prefetch limits may still apply. The `:prefetch_size` is ignored
      if the no-ack option is set.
    * `:prefetch_count` - Specifies a prefetch window in terms of whole
      messages. This field may be used in combination with the `:prefetch_size`
      field; a message will only be sent in advance if both prefetch windows
      (and those at the channel and connection level) allow it. The
      `:prefetch_count` is ignored if the no-ack option is set.
    * `:global` - RabbitMQ takes global=false to mean that the QoS settings
      should apply per-consumer (for new consumers on the channel; existing
      ones being unaffected) and global=true to mean that the QoS settings
      should apply per-channel

  ## Example

    iex> %Freddy.QoS{prefetch_count: 10}
  """

  use Freddy.AMQP, prefetch_count: 0, prefetch_size: 0, global: false

  @doc """
  Returns default configuration for QoS
  """
  @spec default() :: t
  def default do
    %__MODULE__{}
  end

  @doc false
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
