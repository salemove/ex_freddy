defmodule Freddy.Mixfile do
  use Mix.Project

  def project do
    [
      app: :freddy,
      version: "0.13.1",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "JSON RPC Client/Server, JSON Publisher-Subscriber over AMQP",
      dialyzer: [flags: [:error_handling, :race_conditions, :underspecs]],
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
      {:amqp, "~> 0.3"},
      {:connection, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:backoff, "~> 1.1"},
      {:ex_doc, "~> 0.16", only: :dev},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:stream_data, "~> 0.4", only: :test}
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
