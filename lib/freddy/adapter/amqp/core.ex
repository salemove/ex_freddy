defmodule Freddy.Adapter.AMQP.Core do
  @moduledoc false

  # borrowed from https://github.com/pma/amqp

  import Record

  defrecord :p_basic,
            :P_basic,
            extract(:P_basic, from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :queue_declare_ok,
            :"queue.declare_ok",
            extract(:"queue.declare_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :queue_bind,
            :"queue.bind",
            extract(:"queue.bind", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :queue_bind_ok,
            :"queue.bind_ok",
            extract(:"queue.bind_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_ack,
            :"basic.ack",
            extract(:"basic.ack", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_consume,
            :"basic.consume",
            extract(:"basic.consume", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_consume_ok,
            :"basic.consume_ok",
            extract(:"basic.consume_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_publish,
            :"basic.publish",
            extract(:"basic.publish", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_return,
            :"basic.return",
            extract(:"basic.return", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_cancel,
            :"basic.cancel",
            extract(:"basic.cancel", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_cancel_ok,
            :"basic.cancel_ok",
            extract(:"basic.cancel_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_deliver,
            :"basic.deliver",
            extract(:"basic.deliver", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_reject,
            :"basic.reject",
            extract(:"basic.reject", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_recover,
            :"basic.recover",
            extract(:"basic.recover", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_declare_ok,
            :"exchange.declare_ok",
            extract(:"exchange.declare_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_delete,
            :"exchange.delete",
            extract(:"exchange.delete", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_delete_ok,
            :"exchange.delete_ok",
            extract(:"exchange.delete_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_bind_ok,
            :"exchange.bind_ok",
            extract(:"exchange.bind_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_unbind,
            :"exchange.unbind",
            extract(:"exchange.unbind", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_unbind_ok,
            :"exchange.unbind_ok",
            extract(:"exchange.unbind_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_qos,
            :"basic.qos",
            extract(:"basic.qos", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_qos_ok,
            :"basic.qos_ok",
            extract(:"basic.qos_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :basic_nack,
            :"basic.nack",
            extract(:"basic.nack", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_declare,
            :"exchange.declare",
            extract(:"exchange.declare", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :queue_declare,
            :"queue.declare",
            extract(:"queue.declare", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :exchange_bind,
            :"exchange.bind",
            extract(:"exchange.bind", from_lib: "rabbit_common/include/rabbit_framing.hrl")

  defrecord :amqp_params_network,
            :amqp_params_network,
            extract(:amqp_params_network, from_lib: "amqp_client/include/amqp_client.hrl")

  defrecord :amqp_params_direct,
            :amqp_params_direct,
            extract(:amqp_params_direct, from_lib: "amqp_client/include/amqp_client.hrl")

  defrecord :amqp_adapter_info,
            :amqp_adapter_info,
            extract(:amqp_adapter_info, from_lib: "amqp_client/include/amqp_client.hrl")

  defrecord :amqp_msg,
            :amqp_msg,
            extract(:amqp_msg, from_lib: "amqp_client/include/amqp_client.hrl")

  @doc "Converts a keyword list into a rabbit_common compatible type tuple"
  def to_type_tuple(fields) when is_list(fields) do
    Enum.map(fields, &to_type_tuple/1)
  end

  def to_type_tuple(:undefined), do: :undefined
  def to_type_tuple({name, type, value}), do: {to_string(name), type, value}

  def to_type_tuple({name, value}) when is_boolean(value) do
    to_type_tuple({name, :bool, value})
  end

  def to_type_tuple({name, value}) when is_bitstring(value) or is_atom(value) do
    to_type_tuple({name, :longstr, to_string(value)})
  end

  def to_type_tuple({name, value}) when is_integer(value) do
    to_type_tuple({name, :long, value})
  end

  def to_type_tuple({name, value}) when is_float(value) do
    to_type_tuple({name, :float, value})
  end
end
