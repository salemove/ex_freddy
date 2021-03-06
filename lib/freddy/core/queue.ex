defmodule Freddy.Core.Queue do
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

      iex> %Freddy.Core.Queue{exclusive: true, auto_delete: true}

  ### Client-named queue

      iex> %Freddy.Core.Queue{name: "notifications", durable: true}
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

  @doc """
  Create queue configuration from keyword list or `Freddy.Core.Queue` structure.
  """
  @spec new(t | Keyword.t()) :: t
  def new(%__MODULE__{} = queue) do
    queue
  end

  def new(config) when is_list(config) do
    struct!(__MODULE__, config)
  end

  @doc false
  @spec declare(t, Freddy.Core.Channel.t()) :: {:ok, t} | {:error, atom}
  def declare(%__MODULE__{name: name, opts: opts} = queue, %{adapter: adapter, chan: chan}) do
    case adapter.declare_queue(chan, name, opts) do
      {:ok, name} -> {:ok, %{queue | name: name}}
      error -> error
    end
  end

  @doc false
  @spec consume(t, pid, Freddy.Core.Channel.t()) :: {:ok, String.t()} | {:error, atom}
  def consume(%__MODULE__{name: name}, consumer_pid, %{adapter: adapter, chan: chan}, opts \\ []) do
    adapter.consume(chan, name, consumer_pid, opts)
  end
end
