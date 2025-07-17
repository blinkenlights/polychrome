defmodule Octopus.Apps.UnderTheSea do
  use Octopus.App, category: :interactive

  require Logger
  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.PerlinNoise

  def name, do: "Under the sea"

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()

    installation_info.panel_width >= 8 and
      installation_info.panel_height >= 8
  end

  defmodule State do
    defstruct panels: %{}, last_tick: nil
  end

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    state = %State{}
    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, %State{last_tick: System.monotonic_time(:millisecond)}}
  end

  def handle_event(event, state) do
    Logger.info("Unhandled event: #{inspect(event)}")
    {:noreply, state}
  end

  def handle_info(
    :tick,
    %State{last_tick: last_tick} = state
  ) do
    now = System.monotonic_time(:millisecond)
    # seconds, never 0
    dt = max((now - last_tick) / 1000, 0.001)

    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    width = panel_count * panel_width
    height = panel_height
    t = :erlang.system_time(:millisecond) / 1000

    Logger.info("Under the sea: tick #{t}")

    big_canvas =
      Enum.reduce(0..(width-1), Canvas.new(width, height), fn x, canvas ->
        Enum.reduce(0..(height-1), canvas, fn y, c ->
          noise = PerlinNoise.multi_octave_noise_3d(x * 0.2, y * 0.2, t * 0.1, 4, 0.5, 0)
          noise = (noise + 1) / 2

          # Test: von schwarz bis cyan
          r = trunc(noise * 255)
          g = trunc(noise * 255)
          b = trunc(255 * noise)
          color = {r, g, b}

          Canvas.put_pixel(c, {x, y}, color)
        end)
      end)

    Octopus.App.update_display(big_canvas)
    {:noreply, %{state | last_tick: now}}
  end
end
