defmodule SurfaceLiveviewTemplate.MixProject do
  use Mix.Project

  def project do
    [
      app: :surface_liveview_template,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        surface_liveview_template: [
          include_executables_for: [:unix],
          steps: [:assemble, :tar]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SurfaceLiveviewTemplate.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.4"},
      {:gnat, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test]},
    ]
  end
end
