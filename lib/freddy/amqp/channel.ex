defmodule Freddy.AMQP.Channel do
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

  def call(channel, message) do
    safe do
      channel
      |> channel_pid()
      |> :amqp_channel.call(message)
    end
  end

  def call(channel, method, message) do
    safe do
      channel
      |> channel_pid()
      |> :amqp_channel.call(method, message)
    end
  end

  def subscribe(channel, basic_consume, subscriber) do
    safe do
      channel
      |> channel_pid()
      |> :amqp_channel.subscribe(basic_consume, subscriber)
    end
  end

  def register_return_handler(channel, return_handler) do
    channel
    |> channel_pid()
    |> :amqp_channel.register_return_handler(return_handler)
  end

  defp channel_pid(%{pid: pid}) do
    pid
  end

  defp channel_pid(pid) when is_pid(pid) do
    pid
  end
end
