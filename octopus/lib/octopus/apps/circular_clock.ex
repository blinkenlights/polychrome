defmodule Octopus.Apps.CircularClock do
  use Octopus.App, category: :animation, output_type: :rgb

  alias Octopus.Canvas

  require Logger

  # Define custom 8x8 bitmaps for all 12 clock numbers
  # Using defbitmap macro from Font module for consistency
  require Octopus.Font
  import Octopus.Font

  @clock_numbers %{
    1 =>
      defbitmap([
        " X ",
        "XX ",
        " X ",
        " X ",
        " X ",
        " X ",
        "XXX"
      ]),
    2 =>
      defbitmap([
        " XXX ",
        "X   X",
        "   X ",
        "  X  ",
        " X   ",
        "X    ",
        "XXXXX"
      ]),
    3 =>
      defbitmap([
        " XXX ",
        "X   X",
        "    X",
        "   X ",
        "    X",
        "X   X",
        " XXX "
      ]),
    4 =>
      defbitmap([
        "X    ",
        "X   X",
        "X   X",
        "XXXXX",
        "    X",
        "    X",
        "    X"
      ]),
    5 =>
      defbitmap([
        "XXXXX",
        "X    ",
        "XXXX ",
        "    X",
        "    X",
        "X   X",
        " XXX "
      ]),
    6 =>
      defbitmap([
        " XXX ",
        "X   X",
        "X    ",
        "XXXX ",
        "X   X",
        "X   X",
        " XXX "
      ]),
    7 =>
      defbitmap([
        "XXXXX",
        "    X",
        "   X ",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  "
      ]),
    8 =>
      defbitmap([
        " XXX ",
        "X   X",
        "X   X",
        " XXX ",
        "X   X",
        "X   X",
        " XXX "
      ]),
    9 =>
      defbitmap([
        " XXX ",
        "X   X",
        "X   X",
        " XXXX",
        "    X",
        "X   X",
        " XXX "
      ]),
    # Custom two-digit numbers designed to fit perfectly in 8x8 panels
    10 =>
      defbitmap([
        " X   XX ",
        "XX  X  X",
        " X  X  X",
        " X  X  X",
        " X  X  X",
        " X  X  X",
        "XXX  XX "
      ]),
    11 =>
      defbitmap([
        " X   X ",
        "XX  XX ",
        " X   X ",
        " X   X ",
        " X   X ",
        " X   X ",
        "XXX XXX"
      ]),
    12 =>
      defbitmap([
        " X   XX ",
        "XX  X  X",
        " X     X",
        " X    X ",
        " X   X  ",
        " X  X   ",
        "XXX XXXX"
      ])
  }

  def name, do: "Circular Clock"

  def icon() do
    # Use the "12" bitmap as the app icon
    render_clock_number(12, false)
  end

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()

    # Only compatible with 12 panel circular arrangements (like Nation2025)
    installation_info.panel_count == 12 and
      Octopus.Installation.arrangement() == :circular and
      installation_info.panel_width == 8 and
      installation_info.panel_height == 8
  end

  # HSL to RGB conversion for rainbow colors
  defp hsl_to_rgb(h, s, l) do
    # Normalize hue to 0-1 range
    h = h / 360.0
    # S and L are already 0-1 range (saturation and lightness)

    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs(:math.fmod(h * 6, 2) - 1))
    m = l - c / 2

    {r1, g1, b1} =
      case trunc(h * 6) do
        0 -> {c, x, 0}
        1 -> {x, c, 0}
        2 -> {0, c, x}
        3 -> {0, x, c}
        4 -> {x, 0, c}
        5 -> {c, 0, x}
        # fallback
        _ -> {c, x, 0}
      end

    # Convert to 0-255 range
    r = trunc((r1 + m) * 255)
    g = trunc((g1 + m) * 255)
    b = trunc((b1 + m) * 255)

    {r, g, b}
  end

  # Get rainbow color for a specific column (0-based index) with hour-based rotation
  defp get_rainbow_color(column, total_columns, hour_offset) do
    # Base hue for this column
    base_hue = column * (360 / total_columns)
    # Add hour-based rotation: each hour shifts the entire rainbow by 30 degrees
    hour_shift = hour_offset * (360 / 12)
    # Final hue with hour rotation applied
    hue = rem(trunc(base_hue + hour_shift), 360)

    # Full saturation for vivid colors
    saturation = 1.0
    # Increased lightness by 50% for brighter rainbow colors
    lightness = 0.375
    hsl_to_rgb(hue, saturation, lightness)
  end

  # Helper function to render our custom clock number bitmaps
  defp render_clock_number(number, transparent_black) do
    pixels = Map.get(@clock_numbers, number, @clock_numbers[1])
    canvas = Canvas.new(8, 8)

    pixels
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {{r, g, b}, i}, canvas ->
      x = rem(i, 8)
      y = div(i, 8)

      # Skip black pixels entirely - don't add them to canvas.pixels map
      # This makes them truly transparent for overlaying
      if transparent_black and r == 0 and g == 0 and b == 0 do
        canvas
      else
        # Only white pixels (X) get added to the canvas
        Canvas.put_pixel(canvas, {x, y}, {r, g, b})
      end
    end)
  end

  def app_init(_) do
    # Configure display for RGB output using modern unified API
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: true,
      supports_grayscale: false,
      easing_interval: 150
    )

    # Get display info for dynamic sizing
    display_info = Octopus.App.get_display_info()

    # Start by showing numbers 1-12
    :timer.send_after(0, :show_next_number)

    {:ok,
     %{
       display_info: display_info,
       phase: :showing_numbers,
       current_number: 1,
       clock_running: false,
       # Keep persistent number canvas that accumulates all numbers
       numbers_canvas: Canvas.new(display_info.width, display_info.height),
       # Background canvas for time indication
       background_canvas: Canvas.new(display_info.width, display_info.height)
     }}
  end

  def handle_info(
        :show_next_number,
        %{
          current_number: number,
          display_info: display_info,
          numbers_canvas: numbers_canvas
        } = state
      )
      when number <= 12 do
    Logger.debug("Showing number: #{number} (using custom bitmap)")

    # Use our custom clock number bitmaps - much simpler!
    panel_canvas = render_clock_number(number, true)

    Logger.debug(
      "Panel canvas created for number #{number}, pixels: #{map_size(panel_canvas.pixels)}"
    )

    # Calculate panel position - panel 1 is at index 0, so number-1
    panel_index = number - 1
    x_offset = panel_index * display_info.panel_width

    # ADD this number to the persistent numbers canvas
    updated_numbers_canvas = Canvas.overlay(numbers_canvas, panel_canvas, offset: {x_offset, 0})

    # Update display with accumulated numbers
    Octopus.App.update_display(updated_numbers_canvas, :rgb, easing_interval: 150)

    if number < 12 do
      # Schedule next number after a delay to create staggered appearance
      # Show all numbers over 1 second
      delay = trunc(1000 / 12)
      :timer.send_after(delay, :show_next_number)
      {:noreply, %{state | current_number: number + 1, numbers_canvas: updated_numbers_canvas}}
    else
      # All numbers shown, start the clock after a brief pause
      :timer.send_after(500, :start_clock)
      {:noreply, %{state | phase: :clock_ready, numbers_canvas: updated_numbers_canvas}}
    end
  end

  # Handle case where show_next_number is called with number > 12 (should not happen)
  def handle_info(:show_next_number, %{current_number: number} = state) when number > 12 do
    Logger.error("show_next_number called with number #{number} > 12, transitioning to clock")
    # Force transition to clock phase
    send(self(), :start_clock)
    {:noreply, %{state | phase: :clock_ready}}
  end

  def handle_info(:start_clock, state) do
    Logger.debug("Starting clock display")

    # Set up timer to update every second
    :timer.send_interval(1000, :update_clock)
    send(self(), :update_clock)

    # Schedule app to quit after 10 seconds
    :timer.send_after(10_000, :quit_app)

    {:noreply, %{state | phase: :showing_time, clock_running: true}}
  end

  def handle_info(
        :update_clock,
        %{
          clock_running: true,
          display_info: display_info,
          numbers_canvas: numbers_canvas,
          background_canvas: background_canvas
        } = state
      ) do
    # Get current time
    {{_year, _month, _day}, {hour, minute, second}} = :calendar.local_time()

    Logger.debug("Updating clock: #{hour}:#{minute}:#{second}")

    # Convert to 12-hour format
    display_hour =
      case hour do
        0 -> 12
        h when h > 12 -> h - 12
        h -> h
      end

    # Clear the background canvas and apply time-based coloring
    cleared_background = Canvas.clear(background_canvas)

    time_background =
      apply_time_coloring(cleared_background, display_info, display_hour, minute, second)

    # Overlay numbers on top of background - now black pixels are truly transparent
    display_canvas = Canvas.overlay(time_background, numbers_canvas)

    # Update display
    Octopus.App.update_display(display_canvas, :rgb, easing_interval: 150)

    {:noreply, %{state | background_canvas: time_background}}
  end

  def handle_info(:quit_app, state) do
    Logger.debug("Clock app finished, going black and stopping")

    # Create a black canvas
    black_canvas = Canvas.new(state.display_info.width, state.display_info.height)

    # Update display to black
    Octopus.App.update_display(black_canvas, :rgb, easing_interval: 150)

    # Stop the app using the proper supervisor method
    Octopus.KioskModeManager.game_finished()

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in CircularClock: #{inspect(msg)}")
    {:noreply, state}
  end

  # Apply time-based coloring to panels (background only)
  defp apply_time_coloring(canvas, display_info, hour, minute, second) do
    # Starting panel (hour position, 1-based)
    start_panel = hour

    # Calculate how many minutes we're into current 5-minute segment
    minute_mod_5 = rem(minute, 5)
    # How many complete 5-minute segments to fill
    complete_segments = div(minute, 5)

    # Time color - a subtle blue background
    time_color = {0, 100, 200}

    # Fill complete 5-minute segments
    canvas =
      if complete_segments > 0 do
        Enum.reduce(0..(complete_segments - 1), canvas, fn i, acc ->
          # Convert to 1-based, wrap around
          panel_num = rem(start_panel - 1 + i, 12) + 1
          fill_panel_with_color(acc, display_info, panel_num, time_color, hour)
        end)
      else
        canvas
      end

    # Fill partial segment based on minutes and seconds with blinking effect
    canvas =
      if complete_segments < 12 do
        current_panel = rem(start_panel - 1 + complete_segments, 12) + 1

        # Calculate total seconds in this 5-minute segment
        total_seconds_in_segment = minute_mod_5 * 60 + second
        # 5 minutes = 300 seconds, 8 columns per panel
        columns_to_fill = round(8 * total_seconds_in_segment / 300)
        # Clamp to 8
        columns_to_fill = min(columns_to_fill, 8)

        # Apply blinking effect: on even seconds, reduce columns by 1 if we have any columns to show
        # This makes the last filled column blink on/off every second
        blinking_columns =
          if rem(second, 2) == 0 and columns_to_fill > 0 do
            columns_to_fill - 1
          else
            columns_to_fill
          end

        fill_panel_partial(
          canvas,
          display_info,
          current_panel,
          time_color,
          blinking_columns,
          hour
        )
      else
        canvas
      end

    canvas
  end

  # Fill entire panel with rainbow colors (column by column)
  defp fill_panel_with_color(canvas, display_info, panel_num, _base_color, hour) do
    panel_index = panel_num - 1
    x_start = panel_index * display_info.panel_width

    # Fill each column with its own rainbow color, rotated by current hour
    Enum.reduce(0..(display_info.panel_width - 1), canvas, fn col, acc ->
      global_column = x_start + col
      color = get_rainbow_color(global_column, display_info.width, hour)
      x = x_start + col
      Canvas.fill_rect(acc, {x, 0}, {x, display_info.panel_height - 1}, color)
    end)
  end

  # Fill panel partially with rainbow colors (left to right, column by column)
  defp fill_panel_partial(canvas, display_info, panel_num, _base_color, columns, hour) do
    if columns > 0 do
      panel_index = panel_num - 1
      x_start = panel_index * display_info.panel_width

      # Fill each column up to 'columns' with its own rainbow color, rotated by current hour
      Enum.reduce(0..(columns - 1), canvas, fn col, acc ->
        global_column = x_start + col
        color = get_rainbow_color(global_column, display_info.width, hour)
        x = x_start + col
        Canvas.fill_rect(acc, {x, 0}, {x, display_info.panel_height - 1}, color)
      end)
    else
      canvas
    end
  end
end
