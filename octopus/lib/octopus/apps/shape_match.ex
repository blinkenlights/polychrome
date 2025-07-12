defmodule Octopus.Apps.ShapeMatch do
  use Octopus.App, category: :animation
  alias Octopus.WebP
  alias Octopus.Canvas
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
    # Always use adjacent panels layout to utilize all available panels
    Octopus.App.configure_display(layout: :adjacent_panels)

    animation_files = ["balls1", "balls2", "balls3"]

    # Load all animations
    loaded_animations =
      animation_files
      |> Enum.map(fn name ->
        {name, WebP.load_animation(name)}
      end)

    # Randomly pick one
    {chosen_name, chosen_animation} = Enum.random(loaded_animations)

    # Get installation info to create tiled animation
    installation_info = get_installation_info()
    panel_count = installation_info.panel_count

    # For each panel, randomly pick an animation
    chosen_per_panel =
      for _ <- 1..panel_count do
        Enum.random(loaded_animations)
      end

    Logger.info("Shape Match initialized with animation: #{chosen_name}")

    send(self(), :tick)
    {:ok, %{
      chosen_per_panel: chosen_per_panel,
      frame_index: 0,
      installation_info: installation_info
    }}
  end

  def handle_info(:tick, %{chosen_per_panel: chosen_per_panel, frame_index: frame_index, installation_info: installation_info} = state) do
    panel_width = installation_info.panel_width
    panel_height = installation_info.panel_height
    panel_count = installation_info.panel_count
    total_width = panel_count * panel_width
    total_height = panel_height

    # Empty canvas for all panels
    tiled_canvas = Canvas.new(total_width, total_height)

    # Get correct frame for panel
    tiled_canvas =
      Enum.with_index(chosen_per_panel)
      |> Enum.reduce(tiled_canvas, fn {{_name, animation}, panel_index}, acc_canvas ->
        # Find correct frame
        {frame_canvas, _duration} = Enum.at(animation, rem(frame_index, length(animation)))

        x_offset = panel_index * panel_width
        Canvas.overlay(acc_canvas, frame_canvas, offset: {x_offset, 0})
      end)

    # Fixed frame length, 100ms
    Process.send_after(self(), :tick, 100)
    Octopus.App.update_display(tiled_canvas)
    {:noreply, %{state | frame_index: frame_index + 1}}
  end


  def handle_event(_, state) do
    {:noreply, state}
  end
end
