defmodule Octopus.AppModePresets.Loader do
  @moduledoc false

  alias Octopus.AppModePresets.LoaderSupport

  @config_root Application.app_dir(:octopus, "priv/app_mode_presets")

  @app_modules %{
    "Elixir.Octopus.Apps.PixelFun" => "pixelfun",
    "Elixir.Octopus.Apps.PixelFun3D" => "pixelfun3d",
    "Elixir.Octopus.Apps.Collective" => "collective",
    "Elixir.Octopus.Apps.Matrix" => "matrix",
    "Elixir.Octopus.Apps.PerlinNoise" => "perlinnoise",
    "Elixir.Octopus.Apps.Ocean" => "ocean",
    "Elixir.Octopus.Apps.Sand" => "sand",
    "Elixir.Octopus.Apps.SparkleMist" => "sparklemist",
    "Elixir.Octopus.Apps.Wood" => "wood",
    "Elixir.Octopus.Apps.Fire" => "fire"
  }

  @doc false
  def app_modules, do: @app_modules

  for {module_str, app_key} <- @app_modules do
    module = String.to_atom(module_str)
    path = Path.join([@config_root, app_key, "#{app_key}-settings.json"])
    @external_resource path
    presets = LoaderSupport.load_file(path, app_key)

    def presets(unquote(module)), do: unquote(Macro.escape(presets))
  end

  def presets(_), do: []
end
