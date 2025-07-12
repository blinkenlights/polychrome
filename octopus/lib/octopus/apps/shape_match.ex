defmodule Octopus.Apps.ShapeMatch do
  use Octopus.App, category: :animation
  alias Octopus.WebP
  alias Octopus.{Canvas, Font, Transitions}
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent
  alias Octopus.Installation

  require Logger

  def name, do: "Shape Match"

  def compatible?() do
    installation_info = get_installation_info()
    installation_info.panel_width >= 8 and
    installation_info.panel_height >= 8
  end

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)

    animation_files = ["balls1", "balls2", "balls3", "lines1", "lines2"]
    loaded_animations = Enum.map(animation_files, fn name -> {name, WebP.load_animation(name)} end)
    {chosen_name, _chosen_animation} = Enum.random(loaded_animations)

    installation_info = get_installation_info()
    panel_count = installation_info.panel_count

    chosen_per_panel = for _ <- 1..panel_count do Enum.random(loaded_animations) end

    Logger.info("Shape Match initialized with animation: #{chosen_name}")

    send(self(), :tick)
    {:ok, %{
      chosen_per_panel: chosen_per_panel,
      frame_index: 0,
      installation_info: installation_info,
      game_over: false,
      game_start_time: System.monotonic_time(:second),
      game_over_animation_index: 0,
      game_over_elapsed: 0
    }}
  end

  def handle_info(:tick, %{game_over: true, game_over_elapsed: elapsed} = state) do
    formatted = format_time(elapsed)
    # Game is over → animate time display
    now = System.monotonic_time(:second)

    # Safety check for game_start_time
    game_start_time = case state.game_start_time do
      nil -> now
      time when is_integer(time) -> time
      _ -> now
    end

    elapsed = now - game_start_time
    formatted = format_time(elapsed)

    font = Font.load("aftb-Afterburner (Sega)")
    panel_width = state.installation_info.panel_width
    panel_height = state.installation_info.panel_height
    panel_count = state.installation_info.panel_count

    # On which panel should the text appear
    active_panel = rem(state.game_over_animation_index, panel_count)

    tiled_canvas = Canvas.new(panel_count * panel_width, panel_height)

    # For each panel, decide whether to show text or leave empty
    tiled_canvas =
      Enum.reduce(0..(panel_count - 1), tiled_canvas, fn panel_index, acc ->
        x_offset = panel_index * panel_width
        canvas_part =
          if panel_index == active_panel do
            Canvas.from_string(formatted, font, 0)
          else
            Canvas.new(panel_width, panel_height)
          end
        Canvas.overlay(acc, canvas_part, offset: {x_offset, 0})
      end)

    Octopus.App.update_display(tiled_canvas)

    Process.send_after(self(), :tick, 500)

    {:noreply, %{state | game_over_animation_index: state.game_over_animation_index + 1}}
  end

  def handle_info(:tick, %{game_over: false, chosen_per_panel: chosen_per_panel, frame_index: frame_index, installation_info: installation_info} = state) do
    panel_width = installation_info.panel_width
    panel_height = installation_info.panel_height
    panel_count = installation_info.panel_count

    tiled_canvas = Canvas.new(panel_count * panel_width, panel_height)

    tiled_canvas =
      Enum.with_index(chosen_per_panel)
      |> Enum.reduce(tiled_canvas, fn {{_name, animation}, panel_index}, acc ->
        {frame_canvas, _duration} = Enum.at(animation, rem(frame_index, length(animation)))
        x_offset = panel_index * panel_width
        Canvas.overlay(acc, frame_canvas, offset: {x_offset, 0})
      end)

    Process.send_after(self(), :tick, 100)
    Octopus.App.update_display(tiled_canvas)
    {:noreply, %{state | frame_index: frame_index + 1}}
  end

  def handle_event(
    %Octopus.Events.Event.Input{type: :button, action: :press, button: button},
    %{chosen_per_panel: chosen_per_panel, installation_info: installation_info, game_start_time: nil} = state
  ) do
    # First button press → game start
    Logger.info("Game start on button #{button} press")
    now = System.monotonic_time(:second)

    handle_event(
      %Octopus.Events.Event.Input{type: :button, action: :press, button: button},
      %{state | game_start_time: now}
    )
  end

  def handle_event(
    %Octopus.Events.Event.Input{type: :button, action: :press, button: button},
    %{chosen_per_panel: chosen_per_panel, installation_info: installation_info} = state
  ) do
    panel_count = installation_info.panel_count
    animation_files = ["balls1", "balls2", "balls3", "lines1", "lines2"]

    Logger.info("Button #{button} pressed")

    if button >= 0 and button < panel_count do
      loaded_animations = Enum.map(animation_files, fn name -> {name, Octopus.WebP.load_animation(name)} end)
      new_animation = Enum.random(loaded_animations)

      updated_chosen_per_panel = List.replace_at(chosen_per_panel, button - 1, new_animation)

      Logger.info("→ new animation for panel #{button}")

      [{first_name, _} | rest] = updated_chosen_per_panel
      all_same? = Enum.all?(rest, fn {name, _} -> name == first_name end)

      if all_same? do
        Logger.info("🎉 Game Over! All panels have the same animation: #{first_name}")
        now = System.monotonic_time(:second)
        elapsed = now - state.game_start_time
        {:noreply, %{state |
          chosen_per_panel: updated_chosen_per_panel,
          game_over: true,
          game_over_animation_index: 0,
          game_over_elapsed: elapsed
        }}
      else
        {:noreply, %{state | chosen_per_panel: updated_chosen_per_panel}}
      end
    else
      {:noreply, state}
    end
  end

  def handle_event(event, state) do
    Logger.info("Unhandled event: #{inspect(event)}")
    {:noreply, state}
  end

  # Helper function for time formatting
  defp format_time(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, secs]) |> IO.iodata_to_binary()
  end
end
