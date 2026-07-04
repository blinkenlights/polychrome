defmodule Octopus.Installation do
  @typedoc """
  Logical position of a pixel in the installation
  """
  @type pixel :: {integer(), integer()}

  @doc """
  Returns ordered panel ids for this installation (logical slots 0..N-1).
  """
  @callback panels() :: [atom()]

  @doc """
  Returns the `{width, height}` layout shape for each panel.
  """
  @callback panel_layout() :: {pos_integer(), pos_integer()}

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

  @doc """
  Returns the network configuration for this installation
  """
  @callback network_config() :: keyword()

  @doc """
  Returns the global speed for this installation
  """
  @callback global_speed() :: float()

  @doc """
  Returns the location coordinates for this installation
  """
  @callback location() :: {float(), float()} | :auto | binary()

  @doc """
  Returns whether automatic brightness adjustment is enabled for this installation
  """
  @callback auto_brightness() :: boolean()

  @doc """
  Returns whether the radar layer should start for this installation.
  """
  @callback radar_enabled() :: boolean()

  @options_schema NimbleOptions.new!(
                    arrangement: [type: {:in, [:linear, :circular]}, required: true],
                    panels: [
                      type: {:list, :atom},
                      required: false,
                      doc: "Ordered panel ids from the hardware catalog (logical slots 0..N-1)."
                    ],
                    panel_layout: [
                      type: {:tuple, [:pos_integer, :pos_integer]},
                      default: {8, 8},
                      doc: "Panel layout shape `{width, height}` when using `panels:`."
                    ],
                    num_panels: [type: :pos_integer, required: true],
                    num_buttons: [type: :non_neg_integer, required: true],
                    num_joysticks: [type: :non_neg_integer, required: true],
                    panel_width: [type: :pos_integer, required: true],
                    panel_height: [type: :pos_integer, required: true],
                    panel_gap: [type: :non_neg_integer, required: true],
                    global_speed: [type: :float, default: 1.0],
                    location: [
                      type:
                        {:or,
                         [
                           # {latitude, longitude}
                           {:tuple, [:float, :float]},
                           # location name for Nominatim
                           :string,
                           # IP-based detection
                           {:in, [:auto]}
                         ]},
                      default: :auto
                    ],
                    auto_brightness: [type: :boolean, default: false],
                    radar_enabled: [
                      type: :boolean,
                      default: true,
                      doc: "When false, the radar layer does not start for this installation."
                    ],
                    network_config: [
                      type: :keyword_list,
                      default: [],
                      keys: [
                        mode: [type: {:in, [:broadcast, :individual]}, default: :broadcast],
                        broadcast_ip: [
                          type:
                            {:or,
                             [
                               :string,
                               {:tuple, [:integer, :integer, :integer, :integer]},
                               {:in, [:auto]}
                             ]},
                          required: false
                        ],
                        panels: [
                          type: {:list, :keyword_list},
                          default: [],
                          doc:
                            "Individual-mode panel targets. Each entry has :address (hostname or IPv4 tuple) and optional :panel_index (firmware PANEL_INDEX, default 1)."
                        ],
                        send_in_dev: [type: :boolean, default: false]
                      ]
                    ],
                    simulator_layouts: [
                      type:
                        {:list,
                         {:keyword_list,
                          [
                            name: [type: :string, required: true],
                            mode: [type: :string, default: "image"],
                            background_image: [type: :string, required: false],
                            pixel_image: [type: :string, required: false],
                            image_size: [
                              type: {:tuple, [:pos_integer, :pos_integer]},
                              required: false
                            ],
                            pixel_size: [
                              type: {:tuple, [:pos_integer, :pos_integer]},
                              required: false
                            ],
                            offset_x: [type: :non_neg_integer, required: false],
                            offset_y: [type: :non_neg_integer, required: false],
                            spacing: [type: :non_neg_integer, required: false]
                          ]}}
                    ]
                  )

  @moduledoc """
  Defines an installation.

  An installation is a collection of panels and buttons.

  The installation is responsible for:

  Supported options:\n#{NimbleOptions.docs(@options_schema)}
  """

  # Helper function for generating image-based layouts (existing logic)
  def generate_image_layout(name, num_panels, panel_width, panel_height, _panel_gap, layout_opts) do
    offset_x = Keyword.fetch!(layout_opts, :offset_x)
    offset_y = Keyword.fetch!(layout_opts, :offset_y)
    spacing = Keyword.fetch!(layout_opts, :spacing)
    {pixel_width, pixel_height} = Keyword.fetch!(layout_opts, :pixel_size)
    {image_width, image_height} = Keyword.fetch!(layout_opts, :image_size)
    background_image = Keyword.fetch!(layout_opts, :background_image)
    pixel_image = Keyword.fetch!(layout_opts, :pixel_image)

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
      width: num_panels * panel_width,
      height: panel_height,
      pixel_size: {pixel_width, pixel_height},
      pixel_margin: {0, 0, 0, 0},
      background_image: background_image,
      pixel_image: pixel_image,
      image_size: {image_width, image_height}
    }
  end

  # Helper function for generating generic layouts
  def generate_generic_layout(
        name,
        num_panels,
        panel_width,
        panel_height,
        panel_gap,
        layout_opts,
        arrangement
      ) do
    # Default pixel size for generic mode
    {pixel_width, pixel_height} = Keyword.get(layout_opts, :pixel_size, {10, 10})

    # Layout dimensions must match frame data structure:
    # Frame data is structured as num_panels * panel_width * panel_height pixels
    # So layout width should be num_panels * panel_width, height should be panel_height
    layout_width = num_panels * panel_width
    layout_height = panel_height

    # Calculate display width based on arrangement
    display_width =
      case arrangement do
        :linear ->
          # Linear: panels in a line with gaps between them
          (num_panels - 1) * (panel_width + panel_gap) + panel_width

        :circular ->
          # Circular: all panels with gaps, including after the last panel
          num_panels * (panel_width + panel_gap)
      end

    # Canvas size matches display size exactly (no extra margins)
    image_width = display_width * pixel_width
    image_height = layout_height * pixel_height

    positions =
      for i <- 0..(num_panels - 1),
          y <- 0..(panel_height - 1),
          x <- 0..(panel_width - 1) do
        # Calculate panel position based on arrangement
        visual_panel_x = i * (panel_width + panel_gap)

        # Position on canvas (no margins)
        canvas_x = visual_panel_x * pixel_width + x * pixel_width
        canvas_y = y * pixel_height

        {canvas_x, canvas_y}
      end

    %Octopus.Layout{
      name: name,
      positions: positions,
      width: layout_width,
      height: layout_height,
      pixel_size: {pixel_width, pixel_height},
      pixel_margin: {0, 0, 0, 0},
      # Empty string for black background
      background_image: "",
      # Empty string for no overlay
      pixel_image: "",
      image_size: {image_width, image_height}
    }
  end

  defmacro __using__(opts) do
    opts =
      opts
      |> Keyword.put_new(:panel_layout, {8, 8})
      |> derive_panel_fields!()
      |> validate_panels!()

    opts = NimbleOptions.validate!(opts, @options_schema)

    arrangement = Keyword.fetch!(opts, :arrangement)
    panels = Keyword.get(opts, :panels, [])
    panel_layout = Keyword.fetch!(opts, :panel_layout)
    num_panels = Keyword.fetch!(opts, :num_panels)
    num_buttons = Keyword.fetch!(opts, :num_buttons)
    num_joysticks = Keyword.fetch!(opts, :num_joysticks)
    panel_width = Keyword.fetch!(opts, :panel_width)
    panel_height = Keyword.fetch!(opts, :panel_height)
    panel_gap = Keyword.fetch!(opts, :panel_gap)
    global_speed = Keyword.fetch!(opts, :global_speed)
    location = Keyword.fetch!(opts, :location)
    auto_brightness = Keyword.fetch!(opts, :auto_brightness)
    radar_enabled = Keyword.fetch!(opts, :radar_enabled)
    network_config = Keyword.fetch!(opts, :network_config)

    width =
      case arrangement do
        :linear -> (num_panels - 1) * (panel_width + panel_gap) + panel_width
        :circular -> num_panels * (panel_width + panel_gap)
      end

    height = panel_height

    simulator_layouts =
      Keyword.fetch!(opts, :simulator_layouts)
      |> Enum.map(fn layout_opts ->
        name = Keyword.fetch!(layout_opts, :name)
        mode = Keyword.get(layout_opts, :mode, "image")

        case mode do
          "generic" ->
            __MODULE__.generate_generic_layout(
              name,
              num_panels,
              panel_width,
              panel_height,
              panel_gap,
              layout_opts,
              arrangement
            )

          "image" ->
            __MODULE__.generate_image_layout(
              name,
              num_panels,
              panel_width,
              panel_height,
              panel_gap,
              layout_opts
            )

          unknown_mode ->
            raise "Unknown simulator layout mode: #{unknown_mode}. Supported modes: 'image', 'generic'"
        end
      end)
      |> Macro.escape()

    quote do
      @behaviour Octopus.Installation

      @impl Octopus.Installation
      def panels, do: unquote(Macro.escape(panels))
      @impl Octopus.Installation
      def panel_layout, do: unquote(panel_layout)
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
      @impl Octopus.Installation
      def network_config, do: unquote(network_config)
      @impl Octopus.Installation
      def global_speed, do: unquote(global_speed)
      @impl Octopus.Installation
      def location, do: unquote(location)
      @impl Octopus.Installation
      def auto_brightness, do: unquote(auto_brightness)
      @impl Octopus.Installation
      def radar_enabled, do: unquote(radar_enabled)
    end
  end

  defp derive_panel_fields!(opts) do
    case Keyword.get(opts, :panels) do
      nil ->
        opts

      panels ->
        {panel_width, panel_height} = Keyword.fetch!(opts, :panel_layout)

        opts
        |> Keyword.put(:num_panels, length(panels))
        |> Keyword.put(:panel_width, panel_width)
        |> Keyword.put(:panel_height, panel_height)
        |> Keyword.update(:network_config, derive_panel_network_config(panels, []), fn nc ->
          derive_panel_network_config(panels, nc)
        end)
    end
  end

  defp derive_panel_network_config(panels, network_config) do
    registry = Octopus.Hardware.registry()

    panel_targets =
      Enum.map(panels, fn id ->
        panel = Map.fetch!(registry, id)
        [address: panel.hostname, panel_index: panel.firmware_panel_index]
      end)

    Keyword.put(network_config, :panels, panel_targets)
  end

  defp validate_panels!(opts) do
    if Keyword.has_key?(opts, :panels) do
      Octopus.Hardware.InstallationValidator.validate!(opts)
    end

    opts
  end

  @behaviour __MODULE__

  defp installation do
    Application.fetch_env!(:octopus, :installation)
  end

  @impl __MODULE__
  def arrangement, do: installation().arrangement()
  @impl __MODULE__
  def panels, do: installation().panels()
  @impl __MODULE__
  def panel_layout, do: installation().panel_layout()
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
  @impl __MODULE__
  def network_config, do: installation().network_config()
  @impl __MODULE__
  def global_speed, do: installation().global_speed()
  @impl __MODULE__
  def location, do: installation().location()
  @impl __MODULE__
  def auto_brightness, do: installation().auto_brightness()
  @impl __MODULE__
  def radar_enabled, do: installation().radar_enabled()

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
