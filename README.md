# Freddy

RPC protocol over RabbitMQ. **In development stage, minor versions prior to 1.0 may include breaking changes**.

[![Build Status](https://travis-ci.org/salemove/ex_freddy.svg?branch=master)](https://travis-ci.org/salemove/ex_freddy)

## Installation

The package can be installed as:

  1. Add `freddy` to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [{:freddy, "~> 0.10.0"}]
  end
  ```

  2. Ensure `freddy` is started before your application:
  ```elixir
  def application do
    [applications: [:freddy]]
  end
  ```
## Usage

  1. Create Freddy connection:
  ```elixir
  {:ok, conn} = Freddy.Connection.start_link()
  ```
    
  2. Create an RPC Client:
  ```elixir
  defmodule AMQPService do
    use Freddy.RPC.Client
    
    @routing_key "amqp-service"
    
    def start_link(conn, initial \\ nil, opts \\ []) do
      Freddy.RPC.Client.start_link(__MODULE__, conn, [], initial, opts)
    end
    
    def ping(client \\ __MODULE__) do
      Freddy.RPC.Client.request(client, @routing_key, %{type: "ping"})
    end
  end
  ```

  3. Put both connection and service under supervision tree (in this case we're registering
  connection process and RPC client process under static names):
  ```elixir
  defmodule MyApp do
    use Application
    
    def start(_type, _args) do
      import Supervisor.Spec
  
      children = [
        worker(Freddy.Connection, [[], [name: Freddy.Connection]]),
        worker(AMQPService, [Freddy.Connection, nil, [name: AMQPService]])
      ]
  
      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  ```
    
  4. You can now use your client:
  ```elixir
  case AMQPService.ping() do
    {:ok, resp} -> 
      IO.puts "Response: #{inspect response}"
      
    {:error, reason} ->
      IO.puts "Something went wrong: #{inspect reason}"
  end
  ```
