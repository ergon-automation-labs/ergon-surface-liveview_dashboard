defmodule BotArmyDashboardLiveview.MixProject do
  use Mix.Project

  def project do
    [
      app: :bot_army_dashboard_liveview,
      version: "0.1.15",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        bot_army_dashboard_liveview: [
          include_executables_for: [:unix],
          steps: [:assemble, :tar]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BotArmyDashboardLiveview.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:plug_cowboy, "~> 2.6"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:gnat, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test]}
    ]
  end
end
