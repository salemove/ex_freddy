defmodule Freddy.Queue do
  @moduledoc """
  Queue configuration
  """

  use Freddy.AMQP, name: "", opts: []

  @spec declare(t, AMQP.Channel.t()) :: {:ok, t} | {:error, atom}
  def declare(%__MODULE__{name: name, opts: opts} = queue, channel) do
    safe_amqp(on_error: {:error, :queue_declare_error}) do
      {:ok, %{queue: name}} = AMQP.Queue.declare(channel, name, opts)
      {:ok, %{queue | name: name}}
    end
  end

  @spec consume(t, pid, AMQP.Channel.t()) :: {:ok, String.t()} | {:error, atom}
  def consume(%__MODULE__{name: name}, consumer_pid, channel, opts \\ []) do
    safe_amqp(on_error: {:error, :consume_error}) do
      AMQP.Basic.consume(channel, name, consumer_pid, opts)
    end
  end
end
