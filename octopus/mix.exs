defmodule Octopus.MixProject do
  use Mix.Project

  def project do
    [
      app: :octopus,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      compilers: [:yecc, :leex] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Octopus.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:usage_rules, "~> 0.1", only: [:dev]},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:ecto_sqlite3_extras, "~> 1.2.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.7"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:finch, "~> 0.13"},
      {:req, "~> 0.5.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.7"},
      {:protobuf, "~> 0.15.0"},
      {:ex_png, "~> 1.0.0"},
      {:easing, "~> 0.3.1"},
      {:cachex, "~> 4.1"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:rustler, "~> 0.36.0"},
      {:telegram, github: "visciang/telegram", tag: "2.1.0"},
      {:chameleon, "~> 2.5"},
      {:live_monaco_editor, "~> 0.2"},
      {:nimble_parsec, "~> 1.4"},
      {:nimble_options, "~> 1.0"},
      {:mdns_lite, "~> 0.8.10"},
      {:oscx, "~> 0.1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev]}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": [
        "cmd npm install --prefix assets",
        "tailwind.install --if-missing",
        "esbuild.install --if-missing"
      ],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
