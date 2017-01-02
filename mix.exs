defmodule Freddy.Mixfile do
  use Mix.Project

  def project do
    [app: :freddy,
     version: "0.1.0",
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :amqp_client, :amqp, :confex, :connection, :poison]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:amqp, "0.1.5"},
      {:amqp_client, git: "https://github.com/jbrisbin/amqp_client.git", branch: "master", override: true},
      {:confex, "~> 1.4.1"},
      {:connection, "~> 1.0"},
      {:poison, "~> 2.0"},
      {:rabbit_common, git: "https://github.com/jbrisbin/rabbit_common.git", override: true}
    ]
  end
end
