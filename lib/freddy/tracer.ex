defmodule Freddy.Tracer do
  require OpenTelemetry.Tracer

  @response_queue_prefix "amq.gen-"

  def add_context_to_opts(opts) do
    Keyword.put(opts, :ctx, OpenTelemetry.Ctx.get_current())
  end

  def attach_context_from_opts(opts) do
    {ctx_opts, remaining_opts} = Keyword.split(opts, [:ctx])
    OpenTelemetry.Ctx.attach(Keyword.fetch!(ctx_opts, :ctx))
    remaining_opts
  end

  def with_send_span(exchange, routing_key, block) do
    destination_kind = if exchange.type == :direct, do: "queue", else: "topic"
    span_name = "#{span_destination(exchange.name, routing_key)} send"

    OpenTelemetry.Tracer.with_span span_name, %{
      attributes: [
        "messaging.system": "rabbitmq",
        "messaging.rabbitmq_routing_key": routing_key,
        "messaging.destination": exchange.name,
        "messaging.destination_kind": destination_kind
      ],
      kind: :producer
    } do
      headers = inject([])

      block.(headers)
    end
  end

  def with_process_span(meta, exchange, mod, block) do
    headers = normalize_headers(Map.get(meta, :headers, []))
    extract(headers)

    routing_key = Map.get(meta, :routing_key)

    parent = OpenTelemetry.Tracer.current_span_ctx()
    links = if parent == :undefined, do: [], else: [OpenTelemetry.link(parent)]

    destination_kind = if exchange.type == :direct, do: "queue", else: "topic"
    span_name = "#{span_destination(exchange.name, routing_key)} process"

    OpenTelemetry.Tracer.with_span %{}, span_name, %{
      attributes: [
        "messaging.system": "rabbitmq",
        "messaging.rabbitmq_routing_key": routing_key,
        "messaging.destination": exchange.name,
        "messaging.destination_kind": destination_kind,
        "messaging.operation": "process",
        "messaging.freddy.worker": to_string(mod)
      ],
      links: links,
      kind: :consumer
    } do
      try do
        block.()
      rescue
        exception ->
          ctx = OpenTelemetry.Tracer.current_span_ctx()
          OpenTelemetry.Span.record_exception(ctx, exception, __STACKTRACE__, [])
          OpenTelemetry.Tracer.set_status(OpenTelemetry.status(:error, ""))

          reraise(exception, __STACKTRACE__)
      end
    end
  end

  defp span_destination(exchange_name, routing_key) do
    if routing_key && String.starts_with?(routing_key, @response_queue_prefix) do
      "#{exchange_name}.(response queue)"
    else
      "#{exchange_name}.#{routing_key}"
    end
  end

  # amqp uses `:undefined` if no headers are present
  defp normalize_headers(:undefined), do: []

  # amqp returns headers in [{key, type, value}, ...] format. Convert these
  # into just [{key, value}].
  defp normalize_headers(headers) do
    Enum.map(headers, fn {key, _type, value} -> {key, value} end)
  end

  defp extract(carrier), do: :otel_propagator_text_map.extract(carrier)
  defp inject(carrier), do: :otel_propagator_text_map.inject(carrier)
end
