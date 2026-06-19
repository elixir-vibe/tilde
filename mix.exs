defmodule Tilde.MixProject do
  use Mix.Project

  def project do
    [
      app: :tilde,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [plt_add_apps: [:ex_unit, :mix]],
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssh, :public_key, :crypto]
    ]
  end

  def cli do
    [
      preferred_envs: [ci: :test, "test.browser": :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:pi_bridge, "== 0.6.21", only: :dev},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:playwright_ex, "~> 0.7.0", only: :test},
      {:reach, "~> 2.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dotenvy, "~> 1.1"},
      {:volt, "~> 0.14"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:vibe_kit, "~> 0.1"},
      {:ecto_sql, "~> 3.13"},
      {:quackdb, "~> 0.5.13"},
      {:jido, "~> 2.3"},
      {:jido_ai, "~> 2.2"},
      {:req_llm, "~> 1.16"},
      {:hammer, "~> 7.0", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:phoenix_live_reload, "~> 1.6", only: [:dev, :test]},
      {:phoenix_html, "~> 4.0", optional: true},
      {:bandit, "~> 1.0", optional: true},
      {:mdex, "~> 0.13.0", optional: true},
      {:lumis, "~> 0.1", optional: true},
      {:igniter, "~> 0.6", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases() do
    [
      "assets.build": ["volt.build --tailwind"],
      "test.browser": ["test --only browser"],
      ci: [
        "format",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "volt.js.check",
        "volt.build --tailwind --no-hash",
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells"
      ]
    ]
  end
end
