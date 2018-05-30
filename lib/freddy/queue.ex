defmodule Freddy.Queue do
  @moduledoc """
  Queue configuration

  ## Fields

    * `:name` - Queue name. If left empty, a server named queue with unique
      name will be declared.
    * `:opts` - Queue options, see below.

  ## Options

    * `:durable` - If set, keeps the Queue between restarts of the broker.
    * `:auto_delete` - If set, deletes the Queue once all subscribers disconnect.
    * `:exclusive` - If set, only one subscriber can consume from the Queue.
    * `:passive` - If set, raises an error unless the queue already exists.
    * `:nowait` - If set, the server will not respond to the method and client
      will not wait for a reply. Default is `false`.
    * `:arguments` - A set of arguments for the declaration. The syntax and semantics
      of these arguments depends on the server implementation.

  ## Examples

  ### Server-named queue

      iex> %Freddy.Queue{exclusive: true, auto_delete: true}

  ### Client-named queue

      iex> %Freddy.Queue{name: "notifications", durable: true}
  """

  @type t :: %__MODULE__{
          name: String.t(),
          opts: options
        }

  @type options :: [
          durable: boolean,
          auto_delete: boolean,
          exclusive: boolean,
          passive: boolean,
          nowait: boolean,
          arguments: Keyword.t()
        ]

  defstruct name: "", opts: []

  import Freddy.Utils.SafeAMQP

  @doc """
  Create queue configuration from keyword list or `Freddy.Queue` structure.
  """
  @spec new(t | Keyword.t()) :: t
  def new(%__MODULE__{} = queue) do
    queue
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  @doc false
  @spec declare(t, AMQP.Channel.t()) :: {:ok, t} | {:error, atom}
  def declare(%__MODULE__{name: name, opts: opts} = queue, channel) do
    safe_amqp(on_error: {:error, :queue_declare_error}) do
      {:ok, %{queue: name}} = AMQP.Queue.declare(channel, name, opts)
      {:ok, %{queue | name: name}}
    end
  end

  @doc false
  @spec consume(t, pid, AMQP.Channel.t()) :: {:ok, String.t()} | {:error, atom}
  def consume(%__MODULE__{name: name}, consumer_pid, channel, opts \\ []) do
    safe_amqp(on_error: {:error, :consume_error}) do
      AMQP.Basic.consume(channel, name, consumer_pid, opts)
    end
  end
end
