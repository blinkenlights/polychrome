defmodule Octopus.Apps.FlappyDot do
  use Octopus.App
  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent

  defmodule State do
    defstruct [
      :canvas,
      :display_info,
      :tick_count,
      :unicorn_x,   # NEU: horizontale Position des Dots
      :unicorn_y,
      :velocity_y,
      :gravity,
      :jump_strength,
      :game_over,
      :obstacles,
      :input_pressed
    ]
  end

  @fps 30
  @unicorn_start_x 5  # Startwert für Dot

  def name(), do: "FlappyDot"

  def app_init(_args) do
    Octopus.App.configure_display(layout: :gapped_panels)
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)

    state = %State{
      canvas: canvas,
      display_info: display_info,
      tick_count: 0,
      unicorn_x: @unicorn_start_x, # NEU
      unicorn_y: div(display_info.height, 2),
      velocity_y: 0,
      gravity: 1,
      jump_strength: -4,
      game_over: false,
      obstacles: generate_obstacles(display_info.width, display_info.height),
      input_pressed: false
    }

    Octopus.App.update_display(canvas)
    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{game_over: true} = state) do
    # Game Over: Einfach alles resetten nach kurzer Pause
    if state.tick_count > 60 do
      new_state = %State{
        state |
        tick_count: 0,
        unicorn_x: @unicorn_start_x, # NEU
        unicorn_y: div(state.display_info.height, 2),
        velocity_y: 0,
        game_over: false,
        obstacles: generate_obstacles(state.display_info.width, state.display_info.height)
      }
      {:noreply, new_state}
    else
      {:noreply, %{state | tick_count: state.tick_count + 1}}
    end
  end

  def handle_info(:tick, %State{} = state) do
    state = %{state | tick_count: state.tick_count + 1}

    # Nur alle 5 Ticks Physik und Dot bewegen
    slow_tick? = rem(state.tick_count, 5) == 0

    {velocity_y, unicorn_y} =
      if slow_tick? do
        v = state.velocity_y + state.gravity
        y = state.unicorn_y + v
        max_y = state.display_info.height - 2
        {if(state.input_pressed, do: state.jump_strength, else: v), max(1, min(y, max_y))}
      else
        {state.velocity_y, state.unicorn_y}
      end

    # Dot horizontal bewegen (anstatt Hindernisse)
    unicorn_x =
      if slow_tick? do
        state.unicorn_x + 1
      else
        state.unicorn_x
      end

    # Hindernisse bleiben statisch
    obstacles = state.obstacles

    # Prüfe Kollision
    game_over = collision?(unicorn_y, unicorn_x, obstacles, state.display_info)

    # Prüfe, ob Dot das Ende erreicht hat (optional: Game Over oder Loop)
    unicorn_x =
      if unicorn_x >= state.display_info.width do
        0 # oder: state.display_info.width - 1
      else
        unicorn_x
      end

    # Zeichne alles
    canvas = Canvas.new(state.display_info.width, state.display_info.height)
    canvas = draw_background(canvas, state.display_info.width, state.display_info.height)
    canvas = draw_obstacles(canvas, obstacles)
    canvas = draw_unicorn(canvas, unicorn_x, unicorn_y)

    Octopus.App.update_display(canvas)

    {:noreply,
     %State{
       state
       | canvas: canvas,
         unicorn_x: unicorn_x,
         unicorn_y: unicorn_y,
         velocity_y: velocity_y,
         obstacles: obstacles,
         game_over: game_over,
         input_pressed: false
     }}
  end

  # Button Input (press + release)
  def handle_event(%InputEvent{type: :button, action: :press}, state) do
    {:noreply, %{state | input_pressed: true}}
  end

  def handle_event(%InputEvent{type: :button, action: :release}, state) do
    {:noreply, %{state | input_pressed: false}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  # Hilfsfunktionen

  defp generate_obstacles(width, height) do
    gap_size = 5  # Größe der Lücke
    Enum.map(0..(div(width, 10)), fn i ->
      gap_pos = Enum.random(2..(height - gap_size - 2))
      if :rand.uniform() > 0.5 do
        # Hindernis von oben
        %{
          x: width + i * 10,
          width: Enum.random(1..5),
          top_height: gap_pos,
          bottom_height: 0
        }
      else
        # Hindernis von unten
        %{
          x: width + i * 10,
          width: Enum.random(1..5),
          top_height: 0,
          bottom_height: height - (gap_pos + gap_size)
        }
      end
    end)
  end

  defp move_obstacles(obstacles, width) do
    obstacles
    |> Enum.map(fn %{x: x, width: w} = o ->
      new_x = x - 1
      if new_x + w < 0 do
        # Reset auf rechts, immer nur oben ODER unten
        if :rand.uniform() > 0.5 do
          %{o | x: width, width: Enum.random(1..5), top_height: Enum.random(1..5), bottom_height: 0}
        else
          %{o | x: width, width: Enum.random(1..5), top_height: 0, bottom_height: Enum.random(1..5)}
        end
      else
        %{o | x: new_x}
      end
    end)
  end

  defp collision?(unicorn_y, unicorn_x, obstacles, display_info) do
    Enum.any?(obstacles, fn %{x: x, width: w, top_height: th, bottom_height: bh} ->
      # Check horizontal overlap
      in_x = unicorn_x >= x and unicorn_x < x + w
      # Check vertical collision
      in_y = unicorn_y <= th or unicorn_y >= (display_info.height - bh)
      in_x and in_y
    end)
  end

  defp draw_background(canvas, width, height) do
    # sky
    canvas =
      Enum.reduce(0..(width - 1), canvas, fn x, can ->
        Canvas.put_pixel(can, {x, 0}, {0, 0, 255})
      end)

    # grou
    Enum.reduce(0..(width - 1), canvas, fn x, can ->
      Canvas.put_pixel(can, {x, height - 1}, {139, 69, 19})
    end)
  end

  defp draw_obstacles(canvas, obstacles) do
    Enum.reduce(obstacles, canvas, fn %{x: x, width: w, top_height: th, bottom_height: bh}, can ->
      can
      |> draw_obstacle_rect(x, 0, w, th, {0, 0, 255}) # oben: Himmelsfarbe
      |> draw_obstacle_rect(x, can.height - bh, w, bh, {139, 69, 19}) # unten: Bodenfarbe
    end)
  end

  defp draw_obstacle_rect(canvas, x, y, w, h, color) do
    Enum.reduce(x..(x + w - 1), canvas, fn cx, can ->
      Enum.reduce(y..(y + h - 1), can, fn cy, can2 ->
        if cx >= 0 and cy >= 0 and cx < canvas.width and cy < canvas.height do
          Canvas.put_pixel(can2, {cx, cy}, color)
        else
          can2
        end
      end)
    end)
  end

  defp draw_unicorn(canvas, x, y) do
    # Weißes Pixel als Kopf
    canvas = Canvas.put_pixel(canvas, {x, y}, {255, 255, 255})

    # Regenbogen-Schweif 3 Pixel dahinter, farbig, falls möglich
    rainbow_colors = [
      {148, 0, 211}, # Violet
      {75, 0, 130},  # Indigo
      {0, 0, 255},   # Blue
      {0, 255, 0},   # Green
      {255, 255, 0}, # Yellow
      {255, 127, 0}, # Orange
      {255, 0, 0}    # Red
    ]

    Enum.reduce(Enum.with_index(rainbow_colors), canvas, fn {color, i}, can ->
      # Schweif hinter Unicorn (links)
      tail_x = x - (i + 1)
      if tail_x >= 0 and y >= 0 and y < can.height do
        Canvas.put_pixel(can, {tail_x, y}, color)
      else
        can
      end
    end)
  end
end
