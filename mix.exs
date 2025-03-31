defmodule Freddy.Mixfile do
  use Mix.Project

  def project do
    [
      app: :freddy,
      version: "0.17.2",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: [
        lint: ["compile", "dialyzer"]
      ],
      deps: deps(),
      package: package(),
      description: "JSON RPC Client/Server, JSON Publisher-Subscriber over AMQP",
      dialyzer: [flags: [:error_handling, :underspecs]],
      docs: [
        extras: ["README.md"],
        main: "readme"
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [extra_applications: [:logger]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:amqp_client, "~> 4.0"},
      {:connection, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:backoff, "~> 1.1"},
      {:opentelemetry_api, "~> 1.0"},
      {:amqp, "~> 4.0", only: :test},
      {:ex_doc, "~> 0.16", only: :dev},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:stream_data, "~> 1.2", only: :test},
      {:opentelemetry, "~> 1.0", only: [:test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["SaleMove TechMovers"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/salemove/ex_freddy"}
    ]
  end
end
