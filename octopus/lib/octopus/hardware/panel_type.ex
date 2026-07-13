defmodule Octopus.Hardware.PanelType do
  @moduledoc """
  Physical description of a reusable LED panel product (matrix, pixel size, gaps, frame).

  Outer dimensions are derived for radar visualization and future simulators.
  The installation's `panel_layout` remains the authoritative logical matrix.
  """

  @enforce_keys [
    :id,
    :reference_matrix,
    :pixel_width_cm,
    :pixel_height_cm,
    :pixel_depth_cm,
    :gap_x_cm,
    :gap_y_cm,
    :frame_left_cm,
    :frame_right_cm,
    :frame_top_cm,
    :frame_bottom_cm,
    :frame_back_cm,
    :depth_mode
  ]
  defstruct [
    :id,
    :reference_matrix,
    :pixel_width_cm,
    :pixel_height_cm,
    :pixel_depth_cm,
    :gap_x_cm,
    :gap_y_cm,
    :frame_left_cm,
    :frame_right_cm,
    :frame_top_cm,
    :frame_bottom_cm,
    :frame_back_cm,
    depth_mode: :pixel_plus_back
  ]

  @type depth_mode :: :pixel_plus_back | :frame_back_only
  @type t :: %__MODULE__{
          id: atom(),
          reference_matrix: {pos_integer(), pos_integer()},
          pixel_width_cm: number(),
          pixel_height_cm: number(),
          pixel_depth_cm: number(),
          gap_x_cm: number(),
          gap_y_cm: number(),
          frame_left_cm: number(),
          frame_right_cm: number(),
          frame_top_cm: number(),
          frame_bottom_cm: number(),
          frame_back_cm: number(),
          depth_mode: depth_mode()
        }

  @doc """
  Returns `{width_cm, height_cm, depth_cm}` outer dimensions of one panel unit.
  """
  @spec outer_dimensions_cm(t()) :: {float(), float(), float()}
  def outer_dimensions_cm(%__MODULE__{} = type) do
    {cols, rows} = type.reference_matrix

    width =
      type.frame_left_cm + cols * type.pixel_width_cm + max(cols - 1, 0) * type.gap_x_cm +
        type.frame_right_cm

    height =
      type.frame_top_cm + rows * type.pixel_height_cm + max(rows - 1, 0) * type.gap_y_cm +
        type.frame_bottom_cm

    depth =
      case type.depth_mode do
        :frame_back_only -> type.frame_back_cm * 1.0
        :pixel_plus_back -> type.pixel_depth_cm + type.frame_back_cm
      end

    {width, height, depth}
  end

  @doc "Pixel width / height aspect ratio."
  @spec pixel_aspect_ratio(t()) :: float()
  def pixel_aspect_ratio(%__MODULE__{pixel_width_cm: w, pixel_height_cm: h}) do
    w / h
  end

  @doc "Center-to-center pixel spacing including gaps."
  @spec pixel_pitch_cm(t()) :: {float(), float()}
  def pixel_pitch_cm(%__MODULE__{} = type) do
    {type.pixel_width_cm + type.gap_x_cm, type.pixel_height_cm + type.gap_y_cm}
  end
end
