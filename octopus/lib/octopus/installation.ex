defmodule Octopus.Installation do
  @typedoc """
  Logical position of a pixel in the installation
  """
  @type pixel :: {integer(), integer()}

  @doc """
  Returns the physical layout of the installation
  """
  @callback arrangement() :: :circular | :linear

  @doc """
  Returns the number of panels in the installation
  """
  @callback num_panels() :: pos_integer()

  @doc """
  Returns the number of joysticks in the installation
  """
  @callback num_joysticks() :: pos_integer()

  @doc """
  Returns the width of a panel in pixels
  """
  @callback panel_width() :: integer()

  @doc """
  Returns the height of a panel in pixels
  """
  @callback panel_height() :: integer()

  @doc """
  Returns the gap between panels in pixels
  """
  @callback panel_gap() :: integer()

  @doc """
  Returns the width of the installation in pixels (including gaps)
  """
  @callback width() :: integer()

  @doc """
  Returns the height of the installation in pixels (including gaps)
  """
  @callback height() :: integer()

  @callback simulator_layouts() :: nonempty_list(Octopus.Layout.t())

  @doc """
  Returns the number of buttons available in this installation
  """
  @callback num_buttons() :: pos_integer()

  @options_schema NimbleOptions.new!(
                    arrangement: [type: {:in, [:linear, :circular]}, required: true],
                    num_panels: [type: :pos_integer, required: true],
                    num_buttons: [type: :non_neg_integer, required: true],
                    num_joysticks: [type: :non_neg_integer, required: true],
                    panel_width: [type: :pos_integer, required: true],
                    panel_height: [type: :pos_integer, required: true],
                    panel_gap: [type: :pos_integer, required: true],
                    simulator_layouts: [
                      type:
                        {:list,
                         {:keyword_list,
                          [
                            name: [type: :string, required: true],
                            background_image: [type: :string, required: true],
                            pixel_image: [type: :string, required: true],
                            image_size: [
                              type: {:tuple, [:pos_integer, :pos_integer]},
                              required: true
                            ],
                            pixel_size: [
                              type: {:tuple, [:pos_integer, :pos_integer]},
                              required: true
                            ],
                            offset_x: [type: :non_neg_integer, required: true],
                            offset_y: [type: :non_neg_integer, required: true],
                            spacing: [type: :non_neg_integer, required: true]
                          ]}}
                    ]
                  )

  @moduledoc """
  Defines an installation.

  An installation is a collection of panels and buttons.

  The installation is responsible for:

  Supported options:\n#{NimbleOptions.docs(@options_schema)}
  """

  defmacro __using__(opts) do
    opts = NimbleOptions.validate!(opts, @options_schema)

    arrangement = Keyword.fetch!(opts, :arrangement)
    num_panels = Keyword.fetch!(opts, :num_panels)
    num_buttons = Keyword.fetch!(opts, :num_buttons)
    num_joysticks = Keyword.fetch!(opts, :num_joysticks)
    panel_width = Keyword.fetch!(opts, :panel_width)
    panel_height = Keyword.fetch!(opts, :panel_height)
    panel_gap = Keyword.fetch!(opts, :panel_gap)
    width = (num_panels - 1) * (panel_width + panel_gap) + panel_width
    height = panel_height

    simulator_layouts =
      Keyword.fetch!(opts, :simulator_layouts)
      |> Enum.map(fn opts ->
        name = Keyword.fetch!(opts, :name)
        offset_x = Keyword.fetch!(opts, :offset_x)
        offset_y = Keyword.fetch!(opts, :offset_y)
        spacing = Keyword.fetch!(opts, :spacing)
        {pixel_width, pixel_height} = Keyword.fetch!(opts, :pixel_size)
        {image_width, image_height} = Keyword.fetch!(opts, :image_size)
        background_image = Keyword.fetch!(opts, :background_image)
        pixel_image = Keyword.fetch!(opts, :pixel_image)

        positions =
          for i <- 0..(num_panels - 1),
              y <- 0..(panel_height - 1),
              x <- 0..(panel_width - 1) do
            {
              offset_x + i * (spacing + pixel_width * panel_width) + x * pixel_width,
              offset_y + y * pixel_height
            }
          end

        %Octopus.Layout{
          name: name,
          positions: positions,
          # Width should match the logical canvas width (including gaps)
          width: (num_panels - 1) * (panel_width + panel_gap) + panel_width,
          height: panel_height,
          pixel_size: {pixel_width, pixel_height},
          pixel_margin: {0, 0, 0, 0},
          background_image: background_image,
          pixel_image: pixel_image,
          image_size: {image_width, image_height}
        }
      end)
      |> Macro.escape()

    quote do
      @behaviour Octopus.Installation

      @impl Octopus.Installation
      def arrangement, do: unquote(arrangement)
      @impl Octopus.Installation
      def num_panels, do: unquote(num_panels)
      @impl Octopus.Installation
      def num_joysticks, do: unquote(num_joysticks)
      @impl Octopus.Installation
      def num_buttons, do: unquote(num_buttons)
      @impl Octopus.Installation
      def panel_width, do: unquote(panel_width)
      @impl Octopus.Installation
      def panel_height, do: unquote(panel_height)
      @impl Octopus.Installation
      def panel_gap, do: unquote(panel_gap)
      @impl Octopus.Installation
      def width, do: unquote(width)
      @impl Octopus.Installation
      def height, do: unquote(height)
      @impl Octopus.Installation
      def simulator_layouts, do: unquote(simulator_layouts)
    end
  end

  @behaviour __MODULE__

  defp installation do
    Application.fetch_env!(:octopus, :installation)
  end

  @impl __MODULE__
  def arrangement, do: installation().arrangement()
  @impl __MODULE__
  def num_panels, do: installation().num_panels()
  @impl __MODULE__
  def num_joysticks, do: installation().num_joysticks()
  @impl __MODULE__
  def panel_width, do: installation().panel_width()
  @impl __MODULE__
  def panel_height, do: installation().panel_height()
  @impl __MODULE__
  def panel_gap, do: installation().panel_gap()
  @impl __MODULE__
  def width, do: installation().width()
  @impl __MODULE__
  def height, do: installation().height()
  @impl __MODULE__
  def simulator_layouts, do: installation().simulator_layouts()
  @impl __MODULE__
  def num_buttons, do: installation().num_buttons()

  @doc """
  Returns the concrete pixel positions of all panels in the installation
  in the order of the panels, taking into account the panel gap.
  """
  def virtual_pixel_positions_per_panel do
    for {pos_x, pos_y} <- panel_positions_in_pixels() do
      for y <- 0..(panel_height() - 1), x <- 0..(panel_width() - 1) do
        {
          pos_x + x,
          pos_y + y
        }
      end
    end
  end

  defp panel_positions_in_pixels do
    for i <- 0..(num_panels() - 1) do
      {i * (panel_width() + panel_gap()), 0}
    end
  end
end
