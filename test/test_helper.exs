ExUnit.start(
  # We're dealing with real RabbitMQ instance which may add latency
  assert_receive_timeout: 500
)

Logger.remove_backend(:console)
