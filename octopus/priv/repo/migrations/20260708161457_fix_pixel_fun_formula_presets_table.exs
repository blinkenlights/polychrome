defmodule Octopus.Repo.Migrations.FixPixelFunFormulaPresetsTable do
  use Ecto.Migration

  # Superseded by 20260708183000_restore_pixel_fun_presets.
  # Kept as no-op so existing migration history stays valid.

  def up, do: :ok
  def down, do: :ok
end
