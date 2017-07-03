defmodule Freddy.Mixfile do
  use Mix.Project

  def project do
    [app: :freddy,
     version: "0.9.0",
     elixir: "~> 1.4",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     package: package(),
     dialyzer: [
       flags: [:error_handling, :race_conditions, :underspecs]]
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
      {:hare, "~> 0.2.0", hex: :salemove_hare},
      {:amqp, "~> 0.2.2"},
      {:poison, ">= 2.0.0"},

      {:mock, "~> 0.2.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false}
    ]
  end

  defp package do
    [maintainers: ["SaleMove TechMovers"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/salemove/ex_freddy"}]
  end
end
