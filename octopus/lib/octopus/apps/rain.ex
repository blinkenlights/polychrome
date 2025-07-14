defmodule Octopus.Apps.Rain do
  use Octopus.App, category: :game

  require Logger
  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Particles

  def name, do: "Rain"

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()
    installation_info.panel_width >= 8 and
      installation_info.panel_height >= 8
  end

  defmodule State do
    defstruct panels: %{}, last_tick: nil
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
  @rain_color {100, 180, 255}

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()
    panels = for i <- 0..(panel_count - 1), into: %{} do
      {i, new_rain_system(panel_width, panel_height)}
    end
    state = %State{panels: panels, last_tick: System.monotonic_time(:millisecond)}
    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def handle_info(:tick, %State{panels: panels, last_tick: last_tick} = state) do
    now = System.monotonic_time(:millisecond)
    dt = max((now - last_tick) / 1000, 0.001) # seconds, never 0

    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    # Update and maybe spawn new drops
    panels =
      panels
      |> Enum.map(fn {i, sys} ->
        sys = maybe_spawn_rain(sys)
        sys = Particles.update(sys, dt)
        sys = maybe_splash(sys)
        {i, sys}
      end)
      |> Enum.into(%{})

    # Draw all panels on a big canvas
    big_canvas = Canvas.new(panel_count * panel_width, panel_height)
    big_canvas =
      Enum.reduce(panels, big_canvas, fn {i, sys}, acc ->
        small = Particles.draw(sys, Canvas.new(panel_width, panel_height))
        Canvas.overlay(acc, small, offset: {i * panel_width, 0})
      end)

    Octopus.App.update_display(big_canvas)
    {:noreply, %State{panels: panels, last_tick: now}}
  end

  defp new_rain_system(width, height) do
    Particles.new(
      width,
      height,
      :math.pi() / 2, # downwards
      0.05,
      [@rain_color],
      0.5, 1.2, # ttl
      18, 28    # speed
    )
  end

  defp maybe_spawn_rain(sys) do
    # Spawn new drop with 30% chance per tick
    if :rand.uniform() < 0.3 do
      x = :rand.uniform() * (sys.width - 1)
      Particles.spawn(sys, {x, 0}, 1)
    else
      sys
    end
  end

  defp maybe_splash(sys) do
    # If a drop is near the bottom, spawn a splash up with 10% chance
    splash_particles =
      sys.particles
      |> Enum.filter(fn p -> p.y > sys.height - 2 end)
      |> Enum.filter(fn _ -> :rand.uniform() < 0.1 end)

    Enum.reduce(splash_particles, sys, fn p, acc ->
      # Splash: spawn 2-3 particles upwards
      splash = Particles.new(acc.width, acc.height, -:math.pi() / 2, 0.3, [@rain_color], 0.2, 0.5, 10, 20)
      splash = Particles.spawn(splash, {p.x, acc.height - 1}, 2)
      %{acc | particles: acc.particles ++ splash.particles}
    end)
  end

  def handle_event(event, state), do: {:noreply, state}
end
