defmodule Freddy.Producer do
  @moduledoc """
  Generic AMQP Producer

  # Usage

    ```elixir
    {:ok, conn} = Freddy.Conn.start_link()
    {:ok, producer} = Freddy.Producer.start_link(conn)

    Freddy.Producer.produce(producer, "queue-name", "payload")
    ```
  """

  use Freddy.GenProducer
end
