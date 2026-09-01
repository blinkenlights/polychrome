defmodule Octopus.Installation do
  @typedoc """
  Logical position of a pixel in the installation
  """
  @type pixel :: {integer(), integer()}

  @doc """
  Returns ordered controller ids for this installation (logical slots 0..N-1).
  """
  @callback panels() :: [atom()]

  @doc """
  Returns ordered panel slots (controller + wiring) for this installation.
  """
  @callback panel_slots() :: [Octopus.Hardware.PanelSlot.t()]

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
  Returns the installation's logical radar configuration, or `nil` when radar
  is not part of this installation.
  """
  @callback radar_config() :: keyword() | nil

  @doc """
  Returns the optional physical panel type id (`:polychrome`, `:pixie`, `:woodstock`), or `nil`.
  """
  @callback panel_type() :: atom() | nil

  @doc """
  Returns outer panel dimensions `{width_cm, height_cm, depth_cm}` when `panel_type/0` is set.
  """
  @callback panel_outer_dimensions_cm() :: {float(), float(), float()} | nil

  @doc """
  Returns the panel type specification struct when `panel_type/0` is set.
  """
  @callback panel_type_spec() :: Octopus.Hardware.PanelType.t() | nil

  @doc """
  Returns the ring radius in meters for circular installations.
  """
  @callback ring_radius_m() :: float()

  @doc """
  Returns which panel (1-based index) faces north (+Y) in circular layouts, or `1`.
  """
  @callback north_panel() :: pos_integer()

  @doc """
  Returns the central platform radius in meters when set, otherwise `nil`.
  """
  @callback platform_radius_m() :: float() | nil

  @doc """
  Height from ground to the bottom edge of each panel in meters, or `nil`
  when not configured (typical Nation pole height: `0.4`).
  """
  @callback panel_bottom_m() :: float() | nil

  @options_schema NimbleOptions.new!(
                    arrangement: [type: {:in, [:linear, :circular]}, required: true],
                    panels: [
                      type: {:list, :keyword_list},
                      required: true,
                      doc:
                        "Ordered panel slots. Each entry must be `[controller: id, wiring: id]`."
                    ],
                    panel_layout: [
                      type: {:tuple, [:pos_integer, :pos_integer]},
                      default: {8, 8},
                      doc: "Panel layout shape `{width, height}` when using `panels:`."
                    ],
                    panel_matrix: [
                      type: {:tuple, [:pos_integer, :pos_integer]},
                      required: false,
                      doc: "Optional alias for `panel_layout`."
                    ],
                    panel_type: [
                      type: {:in, [:polychrome, :pixie, :woodstock]},
                      required: false,
                      doc: "Physical panel product type for derived dimensions."
                    ],
                    circular: [
                      type: :keyword_list,
                      required: false,
                      keys: [
                        ring_radius_m: [
                          type: :float,
                          required: true,
                          doc: "Outer panel ring radius in meters."
                        ],
                        north_panel: [
                          type: :pos_integer,
                          default: 1,
                          doc: "Panel number (1-based) at north (+Y) in radar / ring views."
                        ],
                        platform_radius_m: [
                          type: :float,
                          required: false,
                          doc:
                            "Central platform radius in meters for radar and mock views; omit to use Sim3D param."
                        ],
                        panel_bottom_m: [
                          type: :float,
                          required: false,
                          doc:
                            "Height from ground to the bottom edge of each panel in meters (e.g. 0.4 for 40 cm posts)."
                        ]
                      ],
                      doc:
                        "Circular arrangement geometry. Required when `arrangement` is `:circular`."
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
                    radar: [
                      type: :keyword_list,
                      required: false,
                      doc:
                        "Logical radar sensor layout for this installation (identifiers, geometry, tuning)."
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

  @doc """
  Builds explicit panel slots for controllers using horizontal serpentine wiring on 8×8 panels.
  """
  @spec standard_8x8_slots([atom()]) :: [[controller: atom(), wiring: atom()]]
  def standard_8x8_slots(controller_ids) do
    Enum.map(controller_ids, fn id ->
      [controller: id, wiring: :serpentine_horizontal_bottom_left]
    end)
  end

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
      |> normalize_panel_layout_alias!()
      |> reject_legacy_arrangement_keys!()
      |> validate_arrangement_geometry!()
      |> Keyword.put_new(:panel_layout, {8, 8})
      |> pre_derive_panel_dimensions!()
      |> validate_radar!()
      |> NimbleOptions.validate!(@options_schema)
      |> parse_panel_slots!()
      |> derive_panel_network_targets!()
      |> validate_panels!()

    panel_slots = Keyword.fetch!(opts, :panel_slots)
    controller_ids = Keyword.fetch!(opts, :panels)

    arrangement = Keyword.fetch!(opts, :arrangement)
    panel_layout = Keyword.fetch!(opts, :panel_layout)
    panel_type = Keyword.get(opts, :panel_type)

    {ring_radius_m, north_panel, platform_radius_m, panel_bottom_m} =
      case arrangement do
        :circular ->
          circular = Keyword.fetch!(opts, :circular)

          {
            Keyword.fetch!(circular, :ring_radius_m),
            Keyword.get(circular, :north_panel, 1),
            Keyword.get(circular, :platform_radius_m),
            Keyword.get(circular, :panel_bottom_m)
          }

        :linear ->
          {nil, 1, nil, nil}
      end

    num_panels = Keyword.fetch!(opts, :num_panels)
    num_buttons = Keyword.fetch!(opts, :num_buttons)
    num_joysticks = Keyword.fetch!(opts, :num_joysticks)
    panel_width = Keyword.fetch!(opts, :panel_width)
    panel_height = Keyword.fetch!(opts, :panel_height)
    panel_gap = Keyword.fetch!(opts, :panel_gap)
    global_speed = Keyword.fetch!(opts, :global_speed)
    location = Keyword.fetch!(opts, :location)
    auto_brightness = Keyword.fetch!(opts, :auto_brightness)

    radar_config =
      opts
      |> Keyword.get(:radar)
      |> normalize_literals()

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

          "strip" ->
            # Panels side by side, even on a ring: the unrolled view.
            %Octopus.Layout{
              __MODULE__.generate_generic_layout(
                name,
                num_panels,
                panel_width,
                panel_height,
                panel_gap,
                layout_opts,
                :linear
              )
              | circularize?: false
            }

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
            raise "Unknown simulator layout mode: #{unknown_mode}. Supported modes: 'image', 'generic', 'strip'"
        end
      end)
      |> Macro.escape()

    ring_radius_fn =
      if arrangement == :circular do
        quote do
          @impl Octopus.Installation
          def ring_radius_m, do: unquote(ring_radius_m)
        end
      else
        quote do
          @impl Octopus.Installation
          def ring_radius_m do
            raise ArgumentError, "ring_radius_m is only defined for circular installations"
          end
        end
      end

    panel_type_fns =
      if panel_type do
        quote do
          @impl Octopus.Installation
          def panel_type, do: unquote(panel_type)

          @impl Octopus.Installation
          def panel_type_spec, do: Octopus.Hardware.PanelTypes.fetch!(unquote(panel_type))

          @impl Octopus.Installation
          def panel_outer_dimensions_cm do
            Octopus.Hardware.PanelType.outer_dimensions_cm(panel_type_spec())
          end
        end
      else
        quote do
          @impl Octopus.Installation
          def panel_type, do: nil

          @impl Octopus.Installation
          def panel_type_spec, do: nil

          @impl Octopus.Installation
          def panel_outer_dimensions_cm, do: nil
        end
      end

    quote do
      @behaviour Octopus.Installation

      @impl Octopus.Installation
      def panels, do: unquote(Macro.escape(controller_ids))
      @impl Octopus.Installation
      def panel_slots, do: unquote(Macro.escape(panel_slots))
      @impl Octopus.Installation
      def panel_layout, do: unquote(panel_layout)
      def panel_matrix, do: panel_layout()
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
      def north_panel, do: unquote(north_panel)

      @impl Octopus.Installation
      def platform_radius_m, do: unquote(Macro.escape(platform_radius_m))

      @impl Octopus.Installation
      def panel_bottom_m, do: unquote(Macro.escape(panel_bottom_m))

      @impl Octopus.Installation
      def radar_config, do: unquote(Macro.escape(radar_config))

      unquote(panel_type_fns)
      unquote(ring_radius_fn)
    end
  end

  defp normalize_panel_layout_alias!(opts) do
    matrix = Keyword.get(opts, :panel_matrix)
    layout = Keyword.get(opts, :panel_layout)

    cond do
      matrix != nil and layout != nil and matrix != layout ->
        raise ArgumentError,
              "panel_matrix #{inspect(matrix)} conflicts with panel_layout #{inspect(layout)}"

      matrix != nil ->
        opts |> Keyword.delete(:panel_matrix) |> Keyword.put(:panel_layout, matrix)

      true ->
        Keyword.delete(opts, :panel_matrix)
    end
  end

  defp reject_legacy_arrangement_keys!(opts) do
    legacy = [:ring_radius_m, :north_panel, :platform_radius_m, :panel_bottom_m]

    case Enum.filter(legacy, &Keyword.has_key?(opts, &1)) do
      [] ->
        opts

      keys ->
        raise ArgumentError,
              "circular-only options #{inspect(keys)} must be set under :circular, not at the top level"
    end
  end

  defp validate_arrangement_geometry!(opts) do
    arrangement = Keyword.fetch!(opts, :arrangement)
    circular? = Keyword.has_key?(opts, :circular)
    num_panels = length(Keyword.fetch!(opts, :panels))

    case arrangement do
      :circular ->
        unless circular? do
          raise ArgumentError, ":circular is required when arrangement is :circular"
        end

        north_panel = opts |> Keyword.fetch!(:circular) |> Keyword.get(:north_panel, 1)

        if north_panel < 1 or north_panel > num_panels do
          raise ArgumentError,
                "circular :north_panel must be between 1 and #{num_panels}, got #{north_panel}"
        end

        opts

      :linear ->
        if circular? do
          raise ArgumentError, ":circular is only allowed when arrangement is :circular"
        end

        opts
    end
  end

  defp pre_derive_panel_dimensions!(opts) do
    panels = Keyword.fetch!(opts, :panels)
    {panel_width, panel_height} = Keyword.fetch!(opts, :panel_layout)

    opts
    |> Keyword.put(:num_panels, length(panels))
    |> Keyword.put(:panel_width, panel_width)
    |> Keyword.put(:panel_height, panel_height)
  end

  defp parse_panel_slots!(opts) do
    entries = Keyword.fetch!(opts, :panels)

    {panel_slots, controller_ids} =
      Enum.map(entries, &parse_panel_entry!/1)
      |> Enum.unzip()

    opts
    |> Keyword.put(:panel_slots, panel_slots)
    |> Keyword.put(:panels, controller_ids)
  end

  defp parse_panel_entry!(entry) when is_list(entry) do
    controller_id = Keyword.get(entry, :controller)
    wiring_id = Keyword.get(entry, :wiring)
    port = Keyword.get(entry, :port, 1)

    allowed = [:controller, :wiring, :port]
    unknown = Keyword.keys(entry) -- allowed

    cond do
      unknown != [] ->
        raise ArgumentError,
              "invalid panel slot #{inspect(entry)}; unknown keys #{inspect(unknown)}"

      not is_atom(controller_id) or not is_atom(wiring_id) ->
        raise ArgumentError,
              "invalid panel slot #{inspect(entry)}; expected [controller: id, wiring: id] with optional port:"

      not (is_integer(port) and port >= 1) ->
        raise ArgumentError,
              "invalid panel slot #{inspect(entry)}; port must be a positive integer"

      true ->
        {%Octopus.Hardware.PanelSlot{
           controller_id: controller_id,
           wiring_id: wiring_id,
           port: port
         }, controller_id}
    end
  end

  defp parse_panel_entry!(entry) do
    raise ArgumentError,
          "invalid panel slot #{inspect(entry)}; expected [controller: id, wiring: id] with optional port:, not bare atoms"
  end

  defp derive_panel_network_targets!(opts) do
    panel_slots = Keyword.fetch!(opts, :panel_slots)

    Keyword.update!(opts, :network_config, fn network_config ->
      derive_panel_network_config(panel_slots, network_config)
    end)
  end

  defp derive_panel_network_config(panel_slots, network_config) do
    registry = Octopus.Hardware.registry()

    panel_targets =
      Enum.map(panel_slots, fn %Octopus.Hardware.PanelSlot{
                                 controller_id: id,
                                 port: slot_port
                               } ->
        controller = Map.fetch!(registry, id)

        [
          address: controller.hostname,
          panel_index: controller.firmware_panel_index,
          port: Octopus.Hardware.Controller.udp_port(controller, slot_port)
        ]
      end)

    Keyword.put(network_config, :panels, panel_targets)
  end

  defp validate_panels!(opts) do
    Octopus.Hardware.InstallationValidator.validate!(opts)
    opts
  end

  defp normalize_literals(nil), do: nil

  defp normalize_literals(list) when is_list(list) do
    Enum.map(list, fn
      {key, value} when is_atom(key) ->
        {key, normalize_literals(value)}

      other ->
        normalize_literals(other)
    end)
  end

  defp normalize_literals({:-, _, [n]}) when is_number(n), do: -n
  defp normalize_literals({:+, _, [n]}) when is_number(n), do: n

  defp normalize_literals(value) when is_atom(value) or is_number(value) or is_boolean(value),
    do: value

  defp normalize_literals(value), do: value

  defp validate_radar!(opts) do
    case Keyword.get(opts, :radar) do
      nil ->
        opts

      radar ->
        layout = Keyword.fetch!(radar, :layout)
        type = Keyword.fetch!(layout, :type)
        sensors = Keyword.fetch!(layout, :sensors)

        unless type == :radial do
          raise ArgumentError, "radar layout :type must be :radial, got #{inspect(type)}"
        end

        Octopus.Radar.SensorPlan.validate_sensor_entries!(sensors)

        opts
    end
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
  def panel_slots, do: installation().panel_slots()
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
  def simulator_layouts do
    info = panel_info()
    {panel_width, panel_height} = panel_layout()
    pixel_count = panel_width * panel_height

    installation().simulator_layouts()
    |> Enum.map(&maybe_circularize_layout/1)
    |> Enum.map(fn %Octopus.Layout{} = layout ->
      %Octopus.Layout{layout | panel_info: info, panel_pixel_count: pixel_count}
    end)
  end

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
  def north_panel, do: installation().north_panel()

  @doc """
  Central platform radius in meters for radar and mock views.

  Uses the installation's `platform_radius_m` when set, otherwise the Sim3D param.
  """
  @impl __MODULE__
  def platform_radius_m do
    case installation().platform_radius_m() do
      nil -> Octopus.Params.Sim3d.platform_radius_m()
      radius -> radius
    end
  end

  @doc """
  Height from ground to panel bottom edge in meters, or `nil` if unset.
  """
  @impl __MODULE__
  def panel_bottom_m, do: installation().panel_bottom_m()

  @impl __MODULE__
  def radar_config, do: installation().radar_config()

  @impl __MODULE__
  def panel_type, do: installation().panel_type()
  @impl __MODULE__
  def panel_type_spec, do: installation().panel_type_spec()
  @impl __MODULE__
  def panel_outer_dimensions_cm, do: installation().panel_outer_dimensions_cm()
  def panel_matrix, do: panel_layout()

  @doc """
  Returns the ring radius in meters for circular installations.

  Raises when the active installation is not circular.
  """
  @impl __MODULE__
  def ring_radius_m do
    if arrangement() == :circular do
      installation().ring_radius_m()
    else
      raise ArgumentError, "ring_radius_m is only defined for circular installations"
    end
  end

  @type panel_position_m :: %{
          required(:panel) => pos_integer(),
          required(:x) => float(),
          required(:y) => float(),
          required(:theta_deg) => float(),
          required(:theta_rad) => float(),
          required(:offset) => non_neg_integer(),
          optional(:label_x) => float(),
          optional(:label_y) => float()
        }

  @type ring_layout_m :: %{
          enabled: true,
          num_panels: pos_integer(),
          north_panel: pos_integer(),
          ring_radius_m: float(),
          platform_radius_m: float() | nil,
          panel_bottom_m: float() | nil,
          panel_width_m: float(),
          panel_depth_m: float(),
          panels: [panel_position_m()],
          gravity_panels: [panel_position_m()]
        }

  @doc """
  Physical panel width in meters from `panel_outer_dimensions_cm/0`, or `0.0`.
  """
  @spec panel_width_m() :: float()
  def panel_width_m do
    case panel_outer_dimensions_cm() do
      {w, _h, _d} -> w / 100.0
      _ -> 0.0
    end
  end

  @doc """
  Physical panel depth in meters from `panel_outer_dimensions_cm/0`, or `0.0`.
  """
  @spec panel_depth_m() :: float()
  def panel_depth_m do
    case panel_outer_dimensions_cm() do
      {_w, _h, d} -> d / 100.0
      _ -> 0.0
    end
  end

  @doc """
  Sensor mount position on the radar ground plane (`x` left/right, `y` front/back).

  Bearing `angle_deg` is measured from **+X**, counter-clockwise (same as
  `Octopus.Radar.Transform.pose_factors/1`). This differs from panel angles,
  which are measured clockwise from **+Y** (north).
  """
  @spec sensor_mount_m(number(), number()) :: {float(), float()}
  def sensor_mount_m(angle_deg, distance_cm)
      when is_number(angle_deg) and is_number(distance_cm) do
    angle_rad = angle_deg * :math.pi() / 180.0
    distance_m = distance_cm / 100.0
    {distance_m * :math.cos(angle_rad), distance_m * :math.sin(angle_rad)}
  end

  @doc """
  World-space panel positions for circular installations (single source of truth).

  Coordinates match the radar ground plane: `x` = left/right, `y` = front/back
  (+Y = north). Panel numbers increase clockwise from `:north_panel`.

  ## Options

    * `:reference` — `:body_center` (default, panel body center at
      `ring_radius_m + panel_depth_m / 2`) or `:inner_face` (inward LED face at
      `ring_radius_m`, for proximity / gravity)
    * `:north_panel` — defaults to `north_panel/0` (installation config). Pass
      a runtime override (e.g. `Radar.north_panel/0`) so views and gravity stay
      aligned when north is adjusted in the UI.
    * `:label_clearance_m` — when set, also includes `label_x` / `label_y` at
      `ring_radius_m + panel_depth_m + clearance` (radar map labels)

  Returns `[]` for non-circular arrangements.
  """
  @spec panel_positions_m(keyword()) :: [panel_position_m()]
  def panel_positions_m(opts \\ []) when is_list(opts) do
    if arrangement() != :circular do
      []
    else
      reference = Keyword.get(opts, :reference, :body_center)
      north = Keyword.get(opts, :north_panel, north_panel())
      label_clearance_m = Keyword.get(opts, :label_clearance_m)

      ring_r = ring_radius_m()
      depth_m = panel_depth_m()
      n_panels = num_panels()
      step_deg = 360.0 / n_panels

      radius_m =
        case reference do
          :inner_face -> ring_r
          :body_center -> ring_r + depth_m / 2.0
        end

      label_r =
        if is_number(label_clearance_m) do
          ring_r + depth_m + label_clearance_m
        else
          nil
        end

      for n <- 1..n_panels do
        offset = Integer.mod(n - north, n_panels)
        theta_deg = offset * step_deg
        theta_rad = theta_deg * :math.pi() / 180.0

        base = %{
          panel: n,
          x: radius_m * :math.sin(theta_rad),
          y: radius_m * :math.cos(theta_rad),
          theta_deg: theta_deg,
          theta_rad: theta_rad,
          offset: offset
        }

        if label_r do
          Map.merge(base, %{
            label_x: label_r * :math.sin(theta_rad),
            label_y: label_r * :math.cos(theta_rad)
          })
        else
          base
        end
      end
    end
  end

  @doc """
  Compact ring layout snapshot for radar / 3D / gravity consumers.

  Returns `nil` when the installation is not circular or has no panel type.
  Panel lists use installation `north_panel/0` unless `:north_panel` is passed.
  """
  @spec ring_layout_m(keyword()) :: ring_layout_m() | nil
  def ring_layout_m(opts \\ []) when is_list(opts) do
    with :circular <- arrangement(),
         type when not is_nil(type) <- panel_type() do
      north = Keyword.get(opts, :north_panel, north_panel())
      position_opts = Keyword.take(opts, [:label_clearance_m]) |> Keyword.put(:north_panel, north)

      %{
        enabled: true,
        num_panels: num_panels(),
        north_panel: north,
        ring_radius_m: ring_radius_m(),
        platform_radius_m: platform_radius_m(),
        panel_bottom_m: panel_bottom_m(),
        panel_width_m: panel_width_m(),
        panel_depth_m: panel_depth_m(),
        panels: panel_positions_m([{:reference, :body_center} | position_opts]),
        gravity_panels: panel_positions_m([{:reference, :inner_face} | position_opts])
      }
    else
      _ -> nil
    end
  end

  @doc """
  Returns world-space panel body-center positions (`%{panel, x, y}`) for
  circular installations. Prefer `panel_positions_m/1` for new code.
  """
  @spec panel_world_positions_m() :: [%{panel: pos_integer(), x: float(), y: float()}]
  def panel_world_positions_m do
    panel_positions_m(reference: :body_center)
    |> Enum.map(&Map.take(&1, [:panel, :x, :y]))
  end

  @doc """
  Returns world-space inner-face panel positions for proximity / gravity.
  Prefer `panel_positions_m/1` with `reference: :inner_face` for new code.
  """
  @spec panel_world_gravity_positions_m() :: [%{panel: pos_integer(), x: float(), y: float()}]
  def panel_world_gravity_positions_m do
    panel_positions_m(reference: :inner_face)
    |> Enum.map(&Map.take(&1, [:panel, :x, :y]))
  end

  @doc """
  Full static world description (panels, sensors, ring, sizes) for the active
  installation. See `Octopus.Installation.World`.
  """
  @spec world_m(keyword()) :: Octopus.Installation.World.t()
  def world_m(opts \\ []), do: Octopus.Installation.World.describe(opts)

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

  # Circular installations show their "generic" (no background image)
  # development layout arranged as a ring, matching the panel order/angles
  # used by `panel_positions_m/1` and `OctopusWeb.RadarLive`'s ring view.
  # Image-backed layouts (annotated photos) are left untouched.
  defp maybe_circularize_layout(%Octopus.Layout{circularize?: false} = layout), do: layout

  defp maybe_circularize_layout(%Octopus.Layout{background_image: bg} = layout)
       when bg in [nil, ""] do
    if arrangement() == :circular do
      Octopus.Installation.CircularLayout.build(layout)
    else
      layout
    end
  end

  defp maybe_circularize_layout(layout), do: layout

  # Static per-panel metadata for the simulator's hover tooltip, in
  # frame-data order (matches every layout's panel blocks, regardless of
  # arrangement/mode).
  defp panel_info do
    {width, height} = panel_layout()

    panel_slots()
    |> Enum.with_index(1)
    |> Enum.map(fn {slot, n} ->
      %{
        panel: n,
        controller: Atom.to_string(slot.controller_id),
        wiring: Atom.to_string(slot.wiring_id),
        width: width,
        height: height
      }
    end)
  end
end
