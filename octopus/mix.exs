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
      deps: deps(),
      usage_rules: usage_rules()
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: :all
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
      {:tidewave, "~> 0.5", only: [:dev]},
      {:usage_rules, "~> 1.2", only: [:dev]},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.22.0"},
      {:ecto_sqlite3_extras, "~> 1.2.0"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.6.2", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:floki, ">= 0.38.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4.1", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.25"},
      {:finch, "~> 0.21"},
      {:req, "~> 0.5.0"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:gettext, ">= 0.0.0"},
      {:bandit, "~> 1.10"},
      {:protobuf, "~> 0.15.0"},
      {:ex_png, "~> 1.0.0"},
      {:easing, "~> 0.3.1"},
      {:cachex, "~> 4.1"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:rustler, "~> 0.36.0"},
      {:chameleon, "~> 2.5"},
      {:live_monaco_editor, "~> 0.2"},
      {:nimble_parsec, "~> 1.4"},
      {:nimble_options, "~> 1.0"},
      {:mdns_lite, "~> 0.9.1"},
      {:oscx, "~> 0.1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.7", only: [:dev]},
      {:circuits_uart, "~> 1.5"}
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
