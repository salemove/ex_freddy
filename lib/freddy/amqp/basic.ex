defmodule Freddy.AMQP.Basic do
  @moduledoc false

  alias Freddy.AMQP.Channel

  import AMQP.Core
  import AMQP.Utils

  def publish(channel, exchange, routing_key, payload, options) do
    {publish_opts, message_props} = Keyword.split(options, [:mandatory, :immediate])

    basic_publish =
      basic_publish(
        exchange: exchange,
        routing_key: routing_key,
        mandatory: Keyword.get(publish_opts, :mandatory, false),
        immediate: Keyword.get(publish_opts, :immediate, false)
      )

    props = build_publish_message_properties(message_props)

    Channel.call(channel, basic_publish, amqp_msg(props: props, payload: payload))
  end

  defp build_publish_message_properties(options) do
    build_publish_message_properties(p_basic(), options)
  end

  defp build_publish_message_properties(message, []) do
    message
  end

  defp build_publish_message_properties(message, [{option, value} | rest]) do
    new_message =
      case option do
        :content_type -> p_basic(message, content_type: value)
        :content_encoding -> p_basic(message, content_encoding: value)
        :headers -> p_basic(message, headers: to_type_tuple(value))
        :persistent -> p_basic(message, delivery_mode: if(value, do: 2, else: 1))
        :priority -> p_basic(message, priority: value)
        :correlation_id -> p_basic(message, correlation_id: value)
        :reply_to -> p_basic(message, reply_to: value)
        :expiration -> p_basic(message, expiration: to_string(value))
        :message_id -> p_basic(message, message_id: value)
        :timestamp -> p_basic(message, timestamp: value)
        :type -> p_basic(message, type: value)
        :user_id -> p_basic(message, user_id: value)
        :app_id -> p_basic(message, app_id: value)
        :cluster_id -> p_basic(message, cluster_id: value)
        _other -> message
      end

    build_publish_message_properties(new_message, rest)
  end

  def consume(channel, queue, consumer_pid, options) do
    basic_consume =
      basic_consume(
        queue: queue,
        consumer_tag: Keyword.get(options, :consumer_tag, ""),
        no_local: Keyword.get(options, :no_local, false),
        no_ack: Keyword.get(options, :no_ack, false),
        exclusive: Keyword.get(options, :exclusive, false),
        nowait: Keyword.get(options, :nowait, false),
        arguments: Keyword.get(options, :arguments, []) |> to_type_tuple()
      )

    case Channel.subscribe(channel, basic_consume, consumer_pid) do
      basic_consume_ok(consumer_tag: consumer_tag) -> {:ok, consumer_tag}
      error -> error
    end
  end

  def qos(channel, options) do
    qos_msg =
      basic_qos(
        prefetch_size: Keyword.get(options, :prefetch_size, 0),
        prefetch_count: Keyword.get(options, :prefetch_count, 0),
        global: Keyword.get(options, :global, false)
      )

    case Channel.call(channel, qos_msg) do
      basic_qos_ok() -> :ok
      error -> error
    end
  end

  def ack(channel, delivery_tag, options \\ []) do
    basic_ack =
      basic_ack(delivery_tag: delivery_tag, multiple: Keyword.get(options, :multiple, false))

    Channel.call(channel, basic_ack)
  end

  def reject(channel, delivery_tag, options \\ []) do
    basic_reject =
      basic_reject(delivery_tag: delivery_tag, requeue: Keyword.get(options, :requeue, true))

    Channel.call(channel, basic_reject)
  end

  def nack(channel, delivery_tag, options \\ []) do
    basic_nack =
      basic_nack(
        delivery_tag: delivery_tag,
        multiple: Keyword.get(options, :multiple, false),
        requeue: Keyword.get(options, :requeue, true)
      )

    Channel.call(channel, basic_nack)
  end

  # convert AMQP message to human-friendly tagged tuple
  def handle_message(basic_consume_ok(consumer_tag: consumer_tag)) do
    {:basic_consume_ok, %{consumer_tag: consumer_tag}}
  end

  def handle_message(basic_cancel(consumer_tag: consumer_tag, nowait: nowait)) do
    {:basic_cancel, %{consumer_tag: consumer_tag, nowait: nowait}}
  end

  def handle_message(basic_cancel_ok(consumer_tag: consumer_tag)) do
    {:basic_cancel_ok, %{consumer_tag: consumer_tag}}
  end

  def handle_message(
        {basic_deliver() = basic_deliver, amqp_msg(props: p_basic() = props, payload: payload)}
      ) do
    basic_deliver(
      consumer_tag: consumer_tag,
      delivery_tag: delivery_tag,
      redelivered: redelivered,
      exchange: exchange,
      routing_key: routing_key
    ) = basic_deliver

    p_basic(
      content_type: content_type,
      content_encoding: content_encoding,
      headers: headers,
      delivery_mode: delivery_mode,
      priority: priority,
      correlation_id: correlation_id,
      reply_to: reply_to,
      expiration: expiration,
      message_id: message_id,
      timestamp: timestamp,
      type: type,
      user_id: user_id,
      app_id: app_id,
      cluster_id: cluster_id
    ) = props

    {:basic_deliver, payload,
     %{
       consumer_tag: consumer_tag,
       delivery_tag: delivery_tag,
       redelivered: redelivered,
       exchange: exchange,
       routing_key: routing_key,
       content_type: content_type,
       content_encoding: content_encoding,
       headers: headers,
       persistent: delivery_mode == 2,
       priority: priority,
       correlation_id: correlation_id,
       reply_to: reply_to,
       expiration: expiration,
       message_id: message_id,
       timestamp: timestamp,
       type: type,
       user_id: user_id,
       app_id: app_id,
       cluster_id: cluster_id
     }}
  end

  def handle_message(
        {basic_return() = return, amqp_msg(props: p_basic() = props, payload: payload)}
      ) do
    basic_return(
      reply_code: reply_code,
      reply_text: reply_text,
      exchange: exchange,
      routing_key: routing_key
    ) = return

    p_basic(
      content_type: content_type,
      content_encoding: content_encoding,
      headers: headers,
      delivery_mode: delivery_mode,
      priority: priority,
      correlation_id: correlation_id,
      reply_to: reply_to,
      expiration: expiration,
      message_id: message_id,
      timestamp: timestamp,
      type: type,
      user_id: user_id,
      app_id: app_id,
      cluster_id: cluster_id
    ) = props

    {:basic_return, payload,
     %{
       reply_code: reply_code,
       reply_text: reply_text,
       exchange: exchange,
       routing_key: routing_key,
       content_type: content_type,
       content_encoding: content_encoding,
       headers: headers,
       persistent: delivery_mode == 2,
       priority: priority,
       correlation_id: correlation_id,
       reply_to: reply_to,
       expiration: expiration,
       message_id: message_id,
       timestamp: timestamp,
       type: type,
       user_id: user_id,
       app_id: app_id,
       cluster_id: cluster_id
     }}
  end

  def handle_message(message) do
    message
  end
end
