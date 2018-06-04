defmodule Freddy.Adapter do
  @moduledoc """
  An interface for AMQP layer
  """

  @type connection :: pid
  @type channel :: pid
  @type error :: atom
  @type options :: Keyword.t()
  @type routing_key :: String.t()
  @type payload :: String.t()
  @type consumer_tag :: String.t()
  @type delivery_tag :: String.t()
  @type meta :: map

  ## Connection management

  @doc """
  Opens AMQP connection with given options. Return `{:ok, connection}` on success
  or `{:error, reason}` on failure.
  """
  @callback open_connection(options | String.t()) :: {:ok, connection} | {:error, error}

  @doc """
  Links current process to a connection
  """
  @callback link_connection(connection) :: :ok

  @doc """
  Closes AMQP connection
  """
  @callback close_connection(connection) :: :ok | {:error, error}

  ## Channel management

  @doc """
  Opens new channel on connection
  """
  @callback open_channel(connection) :: {:ok, channel} | {:error, error}

  @doc """
  Sets up a monitor on a channel
  """
  @callback monitor_channel(channel) :: reference

  @doc """
  Closes existing channel
  """
  @callback close_channel(channel) :: :ok | {:error, error}

  @doc """
  Registers given process as a return handler for the given channel
  """
  @callback register_return_handler(channel, pid) :: :ok

  ## Exchanges

  @type exchange_name :: String.t()
  @type exchange_type :: atom | String.t()

  @doc """
  Declares exchange of the given type on the channel
  """
  @callback declare_exchange(channel, exchange_name, exchange_type, options) ::
              :ok | {:error, error}

  @doc """
  Binds given exchange to another exchange
  """
  @callback bind_exchange(channel, destination :: exchange_name, source :: exchange_name, options) ::
              :ok | {:error, error}

  ## Queues

  @type queue_name :: String.t()
  @type queue_opts :: Keyword.t()

  @doc """
  Declares queue with the given name on the channel
  """
  @callback declare_queue(channel, queue_name, options) :: {:ok, queue_name} | {:error, error}

  @doc """
  Binds given queue to the exchange
  """
  @callback bind_queue(channel, queue_name, exchange_name, options) :: :ok | {:error, error}

  ## Basic

  @doc """
  Publishes a message to an exchange
  """
  @callback publish(channel, exchange_name, routing_key, payload, options) :: :ok | {:error, error}

  @doc """
  Registers given pid as a consumer from a queue
  """
  @callback consume(channel, queue_name, consumer :: pid, options) ::
              {:ok, consumer_tag} | {:error, error}

  @doc """
  Set up channel QoS
  """
  @callback qos(channel, options :: Keyword.t()) :: :ok | {:error, error}

  @doc """
  Acks a message
  """
  @callback ack(channel, delivery_tag, options) :: :ok | {:error, error}

  @doc """
  Nacks a message
  """
  @callback nack(channel, delivery_tag, options) :: :ok | {:error, error}

  @doc """
  Rejects a message
  """
  @callback reject(channel, delivery_tag, options) :: :ok | {:error, error}

  @doc """
  Transforms a message received by a consumed pid into one of the well defined terms
  expected by consumers.
  The expected terms are:
    * `{:consume_ok, meta}` - `consume-ok` message sent by the AMQP server when a consumer is started
    * `{:deliver, payload, meta}` - an actual message from the queue being consumed
    * `{:cancel_ok, meta}` - `cancel-ok` message sent by the AMQP server when a consumer is started
    * `{:cancel, meta}` - `cancel` message sent by the AMQP server when a consumer has been unexpectedly closed
    * `{:return, payload meta}` - `return` message sent by the AMQP server when message could not be routed
    * `:unknown` - any other message
  """
  @callback handle_message(message :: term) ::
              {:consume_ok, meta}
              | {:deliver, payload, meta}
              | {:cancel_ok, meta}
              | {:cancel, meta}
              | {:return, payload, meta}
              | :unknown

  @doc false
  def get(:amqp) do
    Freddy.Adapter.AMQP
  end

  def get(adapter) do
    adapter
  end
end
