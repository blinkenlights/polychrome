defmodule Octopus.Apps.Rickroll do
  use Octopus.App, category: :animation

  alias Octopus.WebP
  alias Octopus.Canvas
  alias Octopus.Protobuf.AudioFrame
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent
  alias Octopus.Installation

  require Logger

  def name, do: "Rickroll"

  def compatible?() do
    # Rickroll is compatible with installations that have at least one panel
    # and 8x8 pixel panels (for proper animation display)
    installation_info = get_installation_info()

    installation_info.panel_count >= 1 and
      installation_info.panel_width >= 8 and
      installation_info.panel_height >= 8
  end

  def app_init(_args) do
    # Always use adjacent panels layout to utilize all available panels
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Load the single-panel rickroll animation
    single_panel_animation = WebP.load_animation("rickroll")

    # Get installation info to create tiled animation
    installation_info = get_installation_info()

    # Create tiled animation that repeats across all panels
    tiled_animation = create_tiled_animation(single_panel_animation, installation_info)

    Logger.info(
      "Rickroll: Tiling single-panel animation across #{installation_info.panel_count} panels with adjacent layout"
    )

    send(self(), :tick)
    {:ok, %{animation: tiled_animation, index: 0}}
  end

  def handle_info(:tick, %{animation: animation, index: index} = state) do
    {canvas, duration} = Enum.at(animation, index)
    Octopus.App.update_display(canvas)
    index = rem(index + 1, length(animation))
    Process.send_after(self(), :tick, duration)
    {:noreply, %{state | index: index}}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    num_buttons = Installation.num_buttons()

    1..num_buttons
    |> Enum.map(&%AudioFrame{uri: "file://rickroll.wav", stop: false, channel: &1})
    |> Enum.each(&send_audio_event/1)

    {:noreply, state}
  end

  def handle_event(_, state) do
    {:noreply, state}
  end

  # Create a tiled animation that repeats the single panel across all available panels
  defp create_tiled_animation(single_panel_animation, installation_info) do
    panel_count = installation_info.panel_count
    panel_width = installation_info.panel_width
    panel_height = installation_info.panel_height

    # Calculate total canvas size for adjacent panels
    total_width = panel_count * panel_width
    total_height = panel_height

    # Transform each frame of the single panel animation into a tiled frame
    Enum.map(single_panel_animation, fn {single_canvas, duration} ->
      # Create a larger canvas to hold all panels
      tiled_canvas = Canvas.new(total_width, total_height)

      # Tile the single panel animation across all panels
      tiled_canvas =
        for panel_index <- 0..(panel_count - 1), reduce: tiled_canvas do
          acc_canvas ->
            x_offset = panel_index * panel_width
            Canvas.overlay(acc_canvas, single_canvas, offset: {x_offset, 0})
        end

      {tiled_canvas, duration}
    end)
  end
end
