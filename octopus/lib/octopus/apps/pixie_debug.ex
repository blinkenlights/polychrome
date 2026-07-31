defmodule Octopus.Apps.PixieDebug do
  use Octopus.App, category: :test

  require Logger

  alias Octopus.AppSupervisor
  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Hardware
  alias Octopus.Hardware.WireMap
  alias Octopus.Installation

  @pixel_walk_mode "pixel_walk"
  @full_panel_mode "full_panel"
  @fade_loop_mode "fade_loop"
  @fade_step_mode "fade_step"
  @max_index 63
  @fps 30
  @frame_time_ms trunc(1000 / @fps)
  @fade_modes [@full_panel_mode, @fade_loop_mode, @fade_step_mode]

  defmodule State do
    defstruct [
      :mode_id,
      :layout_index,
      :color_channel,
      :color,
      :peak_brightness,
      :fade_half_duration_ms,
      :frame_count,
      :frame_index,
      :hardware_easing_ms,
      :phase_ms,
      :next_tick_at,
      :tick_ref,
      :display_info
    ]
  end

  def name(), do: "Pixie Debug"

  def rotation_eligible?(), do: false

  def compatible?() do
    installation = Octopus.App.get_installation_info()

    installation.panel_count == 1 and installation.panel_width == 8 and
      installation.panel_height == 8
  end

  def list_modes do
    [
      %{
        id: @pixel_walk_mode,
        name: "Pixel walk",
        accent_color: "#888888",
        summary: "Walk a single white pixel across the panel for wiring debug",
        builtin: true
      },
      %{
        id: @full_panel_mode,
        name: "Full panel",
        accent_color: "#6d7cff",
        summary: "Fill the entire 8×8 panel with white or RGB color",
        builtin: true
      },
      %{
        id: @fade_loop_mode,
        name: "Fade loop",
        accent_color: "#44aa88",
        summary: "Continuous fade dark → bright → dark for easing debug",
        builtin: true
      },
      %{
        id: @fade_step_mode,
        name: "Fade step",
        accent_color: "#aa6644",
        summary: "Advance one fade frame per button press",
        builtin: true
      }
    ]
  end

  def mode_config(mode_id), do: mode_config_for(mode_id)

  def mode_tweakables(mode_id), do: mode_tweakables_for(mode_id)

  def apply_mode(app_id, mode_id) do
    AppSupervisor.update_config(app_id, mode_config(to_string(mode_id)))
  end

  def config_schema do
    %{
      mode_id: {"Mode", :internal, %{default: @pixel_walk_mode}},
      layout_index:
        {"Layout index", :int,
         %{
           min: 0,
           max: @max_index,
           default: 0,
           visible_when: {:mode_id, [@pixel_walk_mode]}
         }},
      color_channel:
        {"Color channel", :select,
         %{
           default: 0,
           options: [{"White", :white}, {"RGB", :rgb}],
           visible_when: {:mode_id, @fade_modes}
         }},
      color:
        {"Color", :color,
         %{
           default: "#ffffff",
           visible_when: {:color_channel, [:rgb]}
         }},
      peak_brightness:
        {"Peak brightness", :int,
         %{
           min: 0,
           max: 255,
           default: 255,
           visible_when: {:mode_id, [@fade_loop_mode, @fade_step_mode]}
         }},
      fade_half_duration_ms:
        {"Fade half duration (ms)", :int,
         %{
           min: 500,
           max: 10_000,
           default: 3000,
           visible_when: {:mode_id, [@fade_loop_mode]}
         }},
      frame_count:
        {"Frame count", :int,
         %{
           min: 10,
           max: 120,
           default: 30,
           visible_when: {:mode_id, [@fade_step_mode]}
         }},
      frame_index:
        {"Frame index", :int,
         %{
           min: 0,
           max: 119,
           default: 0,
           visible_when: {:mode_id, [@fade_step_mode]}
         }},
      hardware_easing_ms:
        {"Hardware easing (ms)", :int,
         %{
           min: 0,
           max: 500,
           default: 0,
           step: 10,
           visible_when: {:mode_id, [@fade_loop_mode, @fade_step_mode]}
         }}
    }
  end

  def get_config(%State{} = state) do
    %{
      mode_id: state.mode_id,
      layout_index: state.layout_index,
      color_channel: state.color_channel,
      color: state.color,
      peak_brightness: state.peak_brightness,
      fade_half_duration_ms: state.fade_half_duration_ms,
      frame_count: state.frame_count,
      frame_index: state.frame_index,
      hardware_easing_ms: state.hardware_easing_ms
    }
  end

  def handle_config(config, %State{} = state) do
    prev_mode = normalize_mode_id(state.mode_id)

    state =
      state
      |> cancel_tick()
      |> apply_config(config)

    state =
      if prev_mode != state.mode_id and state.mode_id in fade_mode_ids() do
        clear_rgb_buffer(state)
        state
      else
        state
      end

    {:noreply, render_state(state)}
  end

  def config_info(%{mode_id: @full_panel_mode} = config) do
    case Map.get(config, :color_channel, :white) do
      :rgb -> "Panel fill · #{Map.get(config, :color, "#ffffff")} (RGB)"
      _ -> "Panel fill · white"
    end
  end

  def config_info(%{mode_id: @fade_loop_mode} = config) do
    "Fade loop · #{config[:fade_half_duration_ms] || 3000} ms half · easing #{config[:hardware_easing_ms] || 0} ms"
  end

  def config_info(%{mode_id: @fade_step_mode} = config) do
    count = config[:frame_count] || 30
    index = config[:frame_index] || 0
    "Fade step · frame #{index}/#{max(count - 1, 0)} · easing #{config[:hardware_easing_ms] || 0} ms"
  end

  def config_info(%{layout_index: layout_index}) do
    info = debug_info(layout_index)

    """
    Layout (#{info.x}, #{info.y})
    Strip position: #{info.strip}
    Firmware buffer index: #{info.firmware_index}
    """
  end

  def config_info(_config), do: nil

  def now_playing_meta(%{mode_id: @full_panel_mode} = config) do
    case Map.get(config, :color_channel, :white) do
      :rgb -> ["Panel fill · #{Map.get(config, :color, "#ffffff")} (RGB)"]
      _ -> ["Panel fill · white"]
    end
  end

  def now_playing_meta(%{mode_id: @fade_loop_mode} = config) do
    [
      "Fade loop · #{Map.get(config, :fade_half_duration_ms, 3000)} ms half-wave",
      "Hardware easing · #{Map.get(config, :hardware_easing_ms, 0)} ms"
    ]
  end

  def now_playing_meta(%{mode_id: @fade_step_mode} = config) do
    count = Map.get(config, :frame_count, 30)
    index = Map.get(config, :frame_index, 0)

    [
      "Frame #{index} / #{max(count - 1, 0)}",
      "Hardware easing · #{Map.get(config, :hardware_easing_ms, 0)} ms"
    ]
  end

  def now_playing_meta(%{mode_id: @pixel_walk_mode, layout_index: layout_index}) do
    info = debug_info(layout_index)

    [
      "Layout (#{info.x}, #{info.y})",
      "Strip position: #{info.strip}",
      "Firmware buffer index: #{info.firmware_index}"
    ]
  end

  def now_playing_meta(%{layout_index: layout_index}) do
    info = debug_info(layout_index)

    [
      "Layout (#{info.x}, #{info.y})",
      "Strip position: #{info.strip}",
      "Firmware buffer index: #{info.firmware_index}"
    ]
  end

  def now_playing_meta(_config), do: []

  def debug_info(layout_index) when is_integer(layout_index) do
    slot = hd(Installation.panel_slots())
    controller = Hardware.fetch!(slot.controller_id)
    wiring = Hardware.fetch_wiring!(slot.wiring_id)
    layout = Installation.panel_layout()
    panel_width = elem(layout, 0)
    {x, y} = layout_coords(layout_index, panel_width)

    strip = WireMap.layout_to_strip(layout_index, wiring, elem(layout, 0), elem(layout, 1))

    firmware_index =
      WireMap.firmware_index_for_layout(x, y, layout, wiring, controller)

    %{x: x, y: y, strip: strip, firmware_index: firmware_index}
  end

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :gapped_panels,
      supports_rgb: true,
      supports_grayscale: true,
      easing_interval: 0
    )

    Octopus.App.subscribe_to_button_events()

    display_info = Octopus.App.get_display_info()

    state =
      %State{display_info: display_info}
      |> apply_config(config)

    render_state(state)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    if normalize_mode_id(state.mode_id) != @fade_loop_mode do
      {:noreply, state}
    else
      next_tick_at = state.next_tick_at + @frame_time_ms
      delay = max(next_tick_at - System.monotonic_time(:millisecond), 1)
      tick_ref = Process.send_after(self(), :tick, delay)

      half_ms = state.fade_half_duration_ms
      cycle_ms = half_ms * 2
      phase_ms = rem(state.phase_ms + @frame_time_ms, max(cycle_ms, 1))

      state = %{
        state
        | phase_ms: phase_ms,
          next_tick_at: next_tick_at,
          tick_ref: tick_ref
      }

      {:noreply, render_fade_frame(state)}
    end
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: button},
        %State{} = state
      )
      when button in [1, 2] do
    case normalize_mode_id(state.mode_id) do
      @pixel_walk_mode when button == 1 ->
        last = max_index(state)
        next_index = if state.layout_index >= last, do: 0, else: state.layout_index + 1
        {:noreply, apply_layout_index(state, next_index)}

      @fade_step_mode ->
        count = max(state.frame_count, 1)

        next_index =
          case button do
            1 -> rem(state.frame_index + 1, count)
            2 -> rem(state.frame_index - 1 + count, count)
          end

        state = %{state | frame_index: next_index}
        {:noreply, render_fade_frame(state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_event(_event, state), do: {:noreply, state}

  @doc false
  def fade_loop_brightness(phase_ms, half_ms) do
    half_ms = max(trunc(half_ms), 1)
    cycle = half_ms * 2
    phase = rem(max(trunc(phase_ms), 0), cycle)

    if phase <= half_ms do
      phase / half_ms
    else
      (cycle - phase) / half_ms
    end
  end

  @doc false
  def fade_step_brightness(frame_index, frame_count) do
    count = max(trunc(frame_count), 1)
    index = frame_index |> trunc() |> max(0) |> min(count - 1)

    if count <= 1 do
      1.0
    else
      index / (count - 1)
    end
  end

  @doc false
  def build_canvas(%State{} = state) do
    case normalize_mode_id(state.mode_id) do
      @full_panel_mode ->
        fill_at_brightness(state.display_info, state.color_channel, state.color, 255, 1.0)

      @fade_loop_mode ->
        t = fade_loop_brightness(state.phase_ms, state.fade_half_duration_ms)

        fill_at_brightness(
          state.display_info,
          state.color_channel,
          state.color,
          state.peak_brightness,
          t
        )

      @fade_step_mode ->
        t = fade_step_brightness(state.frame_index, state.frame_count)

        fill_at_brightness(
          state.display_info,
          state.color_channel,
          state.color,
          state.peak_brightness,
          t
        )

      _ ->
        canvas = Canvas.new(state.display_info.width, state.display_info.height)
        {x, y} = layout_coords(state.layout_index, state.display_info.panel_width)

        case state.display_info.panel_to_global_coords.(0, x, y) do
          :invalid_panel ->
            canvas

          {gx, gy} ->
            Canvas.put_pixel(canvas, {gx, gy}, {255, 255, 255})
        end
    end
  end

  defp mode_config_for(@pixel_walk_mode),
    do: %{mode_id: @pixel_walk_mode, layout_index: 0}

  defp mode_config_for(@full_panel_mode),
    do: %{mode_id: @full_panel_mode, color_channel: :white, color: "#ffffff"}

  defp mode_config_for(@fade_loop_mode) do
    %{
      mode_id: @fade_loop_mode,
      color_channel: :white,
      color: "#ffffff",
      peak_brightness: 255,
      fade_half_duration_ms: 3000,
      hardware_easing_ms: 0
    }
  end

  defp mode_config_for(@fade_step_mode) do
    %{
      mode_id: @fade_step_mode,
      color_channel: :white,
      color: "#ffffff",
      peak_brightness: 255,
      frame_count: 30,
      frame_index: 0,
      hardware_easing_ms: 0
    }
  end

  defp mode_config_for(_), do: %{}

  defp mode_tweakables_for(@pixel_walk_mode) do
    [
      %{
        key: :layout_index,
        label: "Layout index",
        type: :slider,
        min: 0,
        max: @max_index,
        step: 1,
        default: 0
      }
    ]
  end

  defp mode_tweakables_for(@full_panel_mode), do: color_tweakables()

  defp mode_tweakables_for(@fade_loop_mode) do
    color_tweakables() ++
      [
        %{
          key: :peak_brightness,
          label: "Peak brightness",
          type: :slider,
          min: 0,
          max: 255,
          step: 1,
          default: 255
        },
        %{
          key: :fade_half_duration_ms,
          label: "Fade half duration (ms)",
          type: :slider,
          min: 500,
          max: 10_000,
          step: 100,
          default: 3000
        },
        hardware_easing_tweakable()
      ]
  end

  defp mode_tweakables_for(@fade_step_mode) do
    color_tweakables() ++
      [
        %{
          key: :peak_brightness,
          label: "Peak brightness",
          type: :slider,
          min: 0,
          max: 255,
          step: 1,
          default: 255
        },
        %{
          key: :frame_count,
          label: "Frame count",
          type: :slider,
          min: 10,
          max: 120,
          step: 1,
          default: 30
        },
        %{
          key: :frame_index,
          label: "Frame index",
          type: :slider,
          min: 0,
          max: 119,
          step: 1,
          default: 0
        },
        hardware_easing_tweakable()
      ]
  end

  defp mode_tweakables_for(_), do: []

  defp color_tweakables do
    [
      %{
        key: :color_channel,
        label: "Color channel",
        type: :choice,
        default: :white,
        options: [{:white, "White"}, {:rgb, "RGB"}]
      },
      %{
        key: :color,
        label: "Color",
        type: :color,
        default: "#ffffff",
        visible_when: {:color_channel, [:rgb]}
      }
    ]
  end

  defp hardware_easing_tweakable do
    %{
      key: :hardware_easing_ms,
      label: "Hardware easing (ms)",
      type: :slider,
      min: 0,
      max: 500,
      step: 10,
      default: 0
    }
  end

  defp apply_config(%State{} = state, config) do
    display_info = state.display_info || Octopus.App.get_display_info()
    frame_count = clamp_int(Map.get(config, :frame_count, state.frame_count || 30), 10, 120)

    %{
      state
      | mode_id:
          config
          |> Map.get(:mode_id, state.mode_id || @pixel_walk_mode)
          |> normalize_mode_id(),
        layout_index:
          config
          |> Map.get(:layout_index, state.layout_index || 0)
          |> normalize_index(display_info),
        color_channel:
          config
          |> Map.get(:color_channel, state.color_channel || :white)
          |> normalize_color_channel(),
        color: Map.get(config, :color, state.color || "#ffffff"),
        peak_brightness:
          config
          |> Map.get(:peak_brightness, state.peak_brightness || 255)
          |> clamp_int(0, 255),
        fade_half_duration_ms:
          config
          |> Map.get(:fade_half_duration_ms, state.fade_half_duration_ms || 3000)
          |> clamp_int(500, 10_000),
        frame_count: frame_count,
        frame_index:
          config
          |> Map.get(:frame_index, state.frame_index || 0)
          |> normalize_frame_index(frame_count),
        hardware_easing_ms:
          config
          |> Map.get(:hardware_easing_ms, state.hardware_easing_ms || 0)
          |> clamp_int(0, 500),
        phase_ms: Map.get(config, :phase_ms, state.phase_ms || 0),
        display_info: display_info
    }
  end

  defp apply_layout_index(%State{} = state, layout_index) do
    state = %{state | layout_index: normalize_index(layout_index, state.display_info)}
    render_state(state)
  end

  defp render_state(%State{} = state) do
    case normalize_mode_id(state.mode_id) do
      @fade_loop_mode ->
        next_tick_at = System.monotonic_time(:millisecond) + @frame_time_ms
        tick_ref = Process.send_after(self(), :tick, @frame_time_ms)
        state = %{state | next_tick_at: next_tick_at, tick_ref: tick_ref}
        render_fade_frame(state)

      @fade_step_mode ->
        render_fade_frame(state)

      @full_panel_mode ->
        canvas = build_canvas(state)

        case state.color_channel do
          :rgb -> Octopus.App.update_display(canvas, :rgb)
          _ -> Octopus.App.update_display(canvas, :grayscale)
        end

        state

      _ ->
        canvas = build_canvas(state)
        Octopus.App.update_display(canvas)
        log_pixel(state)
        state
    end
  end

  defp render_fade_frame(%State{} = state) do
    canvas = build_canvas(state)
    easing = state.hardware_easing_ms || 0

    case state.color_channel do
      :rgb -> Octopus.App.update_display(canvas, :rgb, easing_interval: easing)
      _ -> Octopus.App.update_display(canvas, :grayscale, easing_interval: easing)
    end

    state
  end

  defp fill_at_brightness(display_info, color_channel, color, peak, t) do
    t = t |> max(0.0) |> min(1.0)
    level = trunc(t * peak) |> max(0) |> min(255)

    case color_channel do
      :rgb ->
        {r, g, b} = parse_hex_color(color)

        Canvas.new(display_info.width, display_info.height, :rgb)
        |> Canvas.fill({trunc(r * t), trunc(g * t), trunc(b * t)})

      _ ->
        Canvas.new(display_info.width, display_info.height, :grayscale)
        |> Canvas.fill(level)
    end
  end

  defp cancel_tick(%State{tick_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | tick_ref: nil}
  end

  defp cancel_tick(%State{} = state), do: state

  defp log_pixel(%State{} = state) do
    info = debug_info(state.layout_index)

    Logger.info("""
    Pixie Debug — layout index #{state.layout_index} at (#{info.x}, #{info.y})
      Wiring strip position: #{info.strip}
      Firmware buffer index driving that position: #{info.firmware_index}
      Note which physical LED actually lit up for layout index #{state.layout_index}
    """)
  end

  defp layout_coords(index, width) do
    {rem(index, width), div(index, width)}
  end

  defp normalize_index(index, display_info) when is_number(index) do
    index |> trunc() |> max(0) |> min(max_index(display_info))
  end

  defp normalize_frame_index(index, frame_count) when is_number(index) and is_number(frame_count) do
    index |> trunc() |> max(0) |> min(max(frame_count - 1, 0))
  end

  defp max_index(%{panel_width: width, panel_height: height}), do: width * height - 1
  defp max_index(_), do: @max_index

  defp clamp_int(value, min, max) when is_number(value) do
    value |> trunc() |> max(min) |> min(max)
  end

  defp parse_hex_color("#" <> hex) when byte_size(hex) == 6 do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 3, 2), 16)
    {r, g, b}
  end

  defp parse_hex_color(_), do: {255, 255, 255}

  defp fade_mode_ids, do: [@fade_loop_mode, @fade_step_mode, @full_panel_mode]

  defp normalize_mode_id(mode_id) when is_atom(mode_id), do: to_string(mode_id)

  defp normalize_mode_id(mode_id) when is_binary(mode_id), do: mode_id

  defp normalize_mode_id(_), do: @pixel_walk_mode

  defp normalize_color_channel(channel) when channel in [:white, :rgb], do: channel
  defp normalize_color_channel("white"), do: :white
  defp normalize_color_channel("rgb"), do: :rgb
  defp normalize_color_channel(0), do: :white
  defp normalize_color_channel(1), do: :rgb
  defp normalize_color_channel(_), do: :white

  defp clear_rgb_buffer(%State{display_info: info}) do
    canvas =
      Canvas.new(info.width, info.height, :rgb)
      |> Canvas.fill({0, 0, 0})

    Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
  end
end
