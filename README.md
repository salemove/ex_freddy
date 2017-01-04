# Freddy

RPC protocol over RabbitMQ. **In development stage**.

## Installation

The package can be installed as:

  1. Add `freddy` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:freddy, github: "salemove/ex_freddy"}]
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
    defmodule MyApp.AMQPService.Connection do
      use Freddy.Conn, otp_app: :my_app
    end
    ```
    
  2. Create RPC Client:
  
    ```elixir
    defmodule MyApp.AMQPService do
      use Freddy.RPC.Client, 
          connection: Freddy.Conn, 
          queue: "QueueName"

      plug Middleware.JSON
          
      def post_message(message),
        do: call(%{action: "post_message", message: message})
        
      def delete_message(id),
        do: call(%{action: "delete_message", id: id})
    end
    ```

  3. Put both connection and service under supervision tree:
  
    ```elixir
    defmodule MyApp do
      use Application
      
      def start(_type, _args) do
        import Supervisor.Spec
    
        children = [
          supervisor(MyApp.AMQPService.Connection, []),
          supervisor(MyApp.AMQPService, [])
        ]
    
        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end
    end
    ```
    
  4. You can now use your client:
  
    ```elixir
    case MyApp.AMQPService.post_message("Hello") do
      {:ok, response} ->
        IO.puts "New message is #{inspect response}"
        
      {:error, reason} ->
        IO.puts "Something went wrong: #{inspect reason}"
    end
    ```
