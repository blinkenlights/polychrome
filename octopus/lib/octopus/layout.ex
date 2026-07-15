defmodule Octopus.Layout do
  @keys [
    :name,
    :positions,
    :width,
    :height,
    :pixel_size,
    :pixel_margin,
    :image_size,
    :background_image,
    :pixel_image
  ]
  @enforce_keys @keys

  # `panel_centers`/`panel_rotations` are only set for the circular
  # arrangement's ring view (see `Octopus.Installation.CircularLayout`). When
  # present, `positions` holds per-pixel offsets relative to that pixel's
  # panel center (pre-rotation) instead of absolute image coordinates, and the
  # simulator rotates+translates each panel as a rigid block around the ring.
  #
  # `panel_info`/`panel_pixel_count` are set on every layout (see
  # `Octopus.Installation.simulator_layouts/0`) so the simulator can show a
  # per-panel tooltip on hover regardless of arrangement/mode.
  defstruct @keys ++
              [:panel_centers, :panel_rotations, :panel_pixel_count, :panel_info]

  @typedoc """
  Position of a pixel in the image, or — for circular ring layouts — a
  pixel's offset relative to its panel's center (see `panel_centers`).
  """
  @type position :: {number(), number()}

  @typedoc """
  Size in pixels
  """
  @type size :: {integer(), integer()}

  @typedoc """
  Static metadata about one physical panel, for hover tooltips in the
  simulator. `panel` is the 1-based panel number matching frame-data order.
  """
  @type panel_info :: %{
          panel: pos_integer(),
          controller: String.t(),
          wiring: String.t(),
          width: pos_integer(),
          height: pos_integer()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          positions: list(position()),
          width: integer(),
          height: integer(),
          pixel_size: size(),
          pixel_margin: {integer(), integer(), integer(), integer()},
          image_size: size(),
          background_image: String.t(),
          pixel_image: String.t(),
          panel_centers: list(position()) | nil,
          panel_rotations: list(number()) | nil,
          panel_pixel_count: pos_integer() | nil,
          panel_info: list(panel_info()) | nil
        }

  @callback layout() :: t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Octopus.Layout
    end
  end

  defimpl JSON.Encoder, for: Octopus.Layout do
    def encode(%Octopus.Layout{} = layout, encoder) do
      encoder.(
        %{
          name: layout.name,
          positions: layout.positions |> Enum.map(&Tuple.to_list/1),
          width: layout.width,
          height: layout.height,
          pixelSize: layout.pixel_size |> Tuple.to_list(),
          pixelMargin: layout.pixel_margin |> Tuple.to_list(),
          imageSize: layout.image_size |> Tuple.to_list(),
          backgroundImage: layout.background_image,
          pixelImage: layout.pixel_image,
          panelCenters: layout.panel_centers && Enum.map(layout.panel_centers, &Tuple.to_list/1),
          panelRotations: layout.panel_rotations,
          panelPixelCount: layout.panel_pixel_count,
          panelInfo: layout.panel_info
        },
        encoder
      )
    end
  end
end
