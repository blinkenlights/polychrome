defmodule Octopus.Hardware.PanelTypes do
  @moduledoc """
  Catalog of physical LED panel types used across installations.
  """

  alias Octopus.Hardware.PanelType

  @types %{
    # 8×8 matrix, square ~19 cm pixels with 3 mm gaps, 1 cm side frame + 2 cm back.
    # Outer: W = 1 + 8×18.9875 + 7×0.3 + 1 = 156 cm
    #        H = 1 + 8×18.9875 + 7×0.3 + 1 = 156 cm
    #        D = 15 + 2 = 17 cm  (pixel depth + back frame)
    polychrome: %PanelType{
      id: :polychrome,
      reference_matrix: {8, 8},
      pixel_width_cm: 18.9875,
      pixel_height_cm: 18.9875,
      pixel_depth_cm: 15.0,
      gap_x_cm: 0.3,
      gap_y_cm: 0.3,
      frame_left_cm: 1.0,
      frame_right_cm: 1.0,
      frame_top_cm: 1.0,
      frame_bottom_cm: 1.0,
      frame_back_cm: 2.0,
      depth_mode: :pixel_plus_back
    },
    # 8×8 matrix, 6×6 cm pixels, no gaps, 4 cm side frame + 2 cm back.
    # Outer: W = 4 + 8×6 + 4 = 56 cm
    #        H = 4 + 8×6 + 4 = 56 cm
    #        D = 5 + 2 = 7 cm  (pixel depth + back frame)
    pixie: %PanelType{
      id: :pixie,
      reference_matrix: {8, 8},
      pixel_width_cm: 6.0,
      pixel_height_cm: 6.0,
      pixel_depth_cm: 5.0,
      gap_x_cm: 0.0,
      gap_y_cm: 0.0,
      frame_left_cm: 4.0,
      frame_right_cm: 4.0,
      frame_top_cm: 4.0,
      frame_bottom_cm: 4.0,
      frame_back_cm: 2.0,
      depth_mode: :pixel_plus_back
    },
    # 1×32 vertical strip, 6×6 cm pixels, 8.5 cm row gap, 144.5 cm bottom frame.
    # Outer: W = 6 cm  (single column, no side frame)
    #        H = 32×6 + 31×8.5 + 144.5 = 600 cm
    #        D = 4 cm  (back frame only; pixel depth not added)
    woodstock: %PanelType{
      id: :woodstock,
      reference_matrix: {1, 32},
      pixel_width_cm: 6.0,
      pixel_height_cm: 6.0,
      pixel_depth_cm: 2.0,
      gap_x_cm: 0.0,
      gap_y_cm: 8.5,
      frame_left_cm: 0.0,
      frame_right_cm: 0.0,
      frame_top_cm: 0.0,
      frame_bottom_cm: 144.5,
      frame_back_cm: 4.0,
      depth_mode: :frame_back_only
    }
  }

  @doc "Returns all panel type ids."
  @spec ids() :: [atom()]
  def ids, do: Map.keys(@types)

  @doc "Returns `%PanelType{}` for `id`, or raises if unknown."
  @spec fetch!(atom()) :: PanelType.t()
  def fetch!(id) when is_atom(id) do
    Map.fetch!(@types, id)
  end

  @doc "Returns `%PanelType{}` for `id`, or `nil`."
  @spec get(atom()) :: PanelType.t() | nil
  def get(id) when is_atom(id), do: Map.get(@types, id)
end
