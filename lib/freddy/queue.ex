defmodule Freddy.Queue do
  @moduledoc """
  Queue configuration
  """

  @type t :: %__MODULE__{}

  defstruct name: "", opts: []

  def new(%__MODULE__{} = queue) do
    queue
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  @spec declare(t, AMQP.Channel.t()) :: {:ok, t} | {:error, atom}
  def declare(%__MODULE__{name: name, opts: opts} = queue, channel) do
    try do
      {:ok, %{queue: name}} = AMQP.Queue.declare(channel, name, opts)
      {:ok, %{queue | name: name}}
    rescue
      MatchError ->
        # amqp 0.x throws MatchError when server responds with non-OK
        {:error, :queue_declare_error}
    end
  end

  @spec consume(t, pid, AMQP.Channel.t()) :: {:ok, String.t()} | {:error, atom}
  def consume(%__MODULE__{name: name}, consumer_pid, channel, opts \\ []) do
    try do
      AMQP.Basic.consume(channel, name, consumer_pid, opts)
    rescue
      MatchError ->
        # amqp 0.x throws MatchError when server responds with non-OK
        {:error, :consume_error}
    end
  end
end
