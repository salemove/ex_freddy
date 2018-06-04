defmodule Freddy.Adapter.AMQP.Channel do
  @moduledoc false

  # see https://www.rabbitmq.com/amqp-0-9-1-reference.html#constants
  @code_to_error %{
    311 => :content_too_large,
    313 => :no_consumers,
    320 => :closed,
    402 => :invalid_path,
    403 => :access_refused,
    404 => :not_found,
    405 => :resource_locked,
    406 => :precondition_failed,
    501 => :frame_error,
    502 => :syntax_error,
    503 => :command_invalid,
    504 => :channel_error,
    505 => :unexpected_frame,
    506 => :resource_error,
    530 => :not_allowed,
    540 => :not_implemented,
    541 => :internal_error
  }

  defmacrop safe(do: expr) do
    quote do
      try do
        case unquote(expr) do
          :closing -> {:error, :closed}
          :blocked -> {:error, :blocked}
          result -> result
        end
      catch
        :exit, {{:shutdown, {:server_initiated_close, code, _}}, _} ->
          {:error, Map.get(@code_to_error, code, :unknown_error)}

        :exit, _ ->
          {:error, :closed}
      end
    end
  end

  def open(connection) do
    case :amqp_connection.open_channel(connection) do
      {:ok, pid} -> {:ok, pid}
      error -> {:error, error}
    end
  end

  def close(pid) do
    try do
      case :amqp_channel.close(pid) do
        :ok -> :ok
        error -> {:error, error}
      end
    catch
      _, _ -> :ok
    end
  end

  defdelegate monitor(pid), to: Process

  def call(channel, message) do
    safe do
      :amqp_channel.call(channel, message)
    end
  end

  def call(channel, method, message) do
    safe do
      :amqp_channel.call(channel, method, message)
    end
  end

  def subscribe(channel, basic_consume, subscriber) do
    safe do
      :amqp_channel.subscribe(channel, basic_consume, subscriber)
    end
  end

  def register_return_handler(channel, return_handler) do
    :amqp_channel.register_return_handler(channel, return_handler)
  end
end
