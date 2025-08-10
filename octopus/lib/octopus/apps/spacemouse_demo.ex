defmodule Octopus.Apps.SpaceMouseDemo do
  @moduledoc """
  Demo app showcasing SpaceMouse integration in Octopus.

  This app demonstrates how to:
  - Enable SpaceMouse support
  - Handle 6DOF motion events  
  - Handle button events
  - Control the SpaceMouse LED
  - Clean up when the app stops

  The app creates visual feedback based on SpaceMouse input:
  - X-axis movement controls hue (color) - speed of change
  - Y-axis movement controls saturation - speed of change  
  - Z-axis movement controls brightness - speed of change
  - Rotation axes (RX, RY, RZ) are ignored for simplicity
  - Button presses toggle the LED state and create temporary color flashes
  
  Movement values act as "speed of change" rather than absolute values:
  - Small movements = extremely slow color changes
  - Large movements = slow color changes  
  - Negative values change in one direction, positive in the other
  - At maximum input (±1.0), it takes ~50 seconds to cycle through full range
  """

  use Octopus.App

  alias Octopus.Events.Event.SpaceMouse, as: SpaceMouseEvent
  alias Octopus.Canvas

  defmodule State do
    @moduledoc false
    defstruct [
      :translation,
      :rotation,
      :led_state,
      :last_button_press,
      :color_base,
      :display_info
    ]
  end

  @impl true
  def name, do: "SpaceMouse Demo"

  @impl true
  def app_init(_config) do
    require Logger
    Logger.info("SpaceMouse Demo: App starting up...")
    
    # Configure display for gapped panels layout
    Octopus.App.configure_display(layout: :gapped_panels)
    display_info = Octopus.App.get_display_info()
    
    # Enable SpaceMouse support
    case Octopus.SpaceMouse.enable() do
      :ok ->
        Logger.info("SpaceMouse Demo: SpaceMouse enabled successfully")
        # Turn on the LED to indicate the app is active
        Octopus.SpaceMouse.set_led(:on)
        
        # Start with random hue, 50% saturation and brightness
        random_hue = :rand.uniform(360) - 1  # Random hue between 0-359
        initial_state = %State{
          translation: %{x: 0.0, y: 0.0, z: 0.0},
          rotation: %{rx: 0.0, ry: 0.0, rz: 0.0},
          led_state: :on,
          last_button_press: nil,
          color_base: %{h: random_hue, s: 50, v: 50},
          display_info: display_info
        }
        
        # Render initial frame
        render_and_update(initial_state)

        {:ok, initial_state}

      {:error, reason} ->
        Logger.error("SpaceMouse Demo: Failed to enable SpaceMouse: #{inspect(reason)}")
        {:stop, {:spacemouse_error, reason}}
    end
  end

  @impl true
  def handle_event(%SpaceMouseEvent{type: :motion, motion: motion}, state) do
    # Update our motion tracking (still track for other uses)
    new_translation = %{x: motion.x, y: motion.y, z: motion.z}
    new_rotation = %{rx: motion.rx, ry: motion.ry, rz: motion.rz}

    # Calculate color changes based on motion
    # X-axis controls hue (0-360 degrees) - speed of change
    # At max value (±1.0), it should take ~50 seconds to cycle through all colors
    hue_change_rate = motion.x * 360.0  # degrees per second at max value
    new_hue = state.color_base.h + hue_change_rate / 500.0  # Assuming ~10 updates per second, reduced by 50x
    new_hue = rem(round(new_hue + 360), 360)  # Keep in 0-360 range

    # Y-axis controls saturation (0-100%) - speed of change  
    # At max value (±1.0), it should take ~14 seconds to go from 0 to 100% (100 / 7.2 steps per second)
    saturation_change_rate = motion.y * 100.0  # percentage per second at max value
    new_saturation = state.color_base.s + saturation_change_rate / 140.0  # Slower than hue but still responsive
    new_saturation = max(0, min(100, round(new_saturation)))  # Keep in 0-100 range

    # Z-axis controls brightness/value (10-100%) - speed of change
    # At max value (±1.0), it should take ~14 seconds to go from 10 to 100% (90 / 6.5 steps per second)
    brightness_change_rate = motion.z * 90.0  # 90% range (100-10)
    new_brightness = state.color_base.v + brightness_change_rate / 140.0  # Same speed as saturation
    new_brightness = max(10, min(100, round(new_brightness)))  # Keep in 10-100 range (never black)

    new_color_base = %{
      state.color_base | 
      h: new_hue, 
      s: new_saturation, 
      v: new_brightness
    }
    
    # Single consolidated log message with motion and resulting color
    require Logger
    Logger.info("SpaceMouse: Motion [X:#{round_to_3(motion.x)} Y:#{round_to_3(motion.y)} Z:#{round_to_3(motion.z)}] → Color [H:#{new_hue}° S:#{new_saturation}% V:#{new_brightness}%]")
    
    new_state = %State{
      state | 
      translation: new_translation,
      rotation: new_rotation,
      color_base: new_color_base
    }
    
    # Render and send frame to panels
    render_and_update(new_state)

    {:noreply, new_state}
  end

  def handle_event(%SpaceMouseEvent{type: :button, button: button}, state) do
    require Logger
    Logger.info("SpaceMouse: Button #{button.id} #{button.state}")
    
    case button.state do
      :pressed ->
        # Toggle LED state on button press
        new_led_state = if state.led_state == :on, do: :off, else: :on
        Octopus.SpaceMouse.set_led(new_led_state)

        # Create a color flash effect
        flash_color = %{state.color_base | s: 100, v: 100}

        new_state = %State{
          state | 
          led_state: new_led_state,
          last_button_press: button.id,
          color_base: flash_color
        }
        
        # Render and send frame to panels
        render_and_update(new_state)

        {:noreply, new_state}

      :released ->
        # Return to normal color on button release
        normal_color = %{state.color_base | s: 100, v: 50}
        new_state = %State{state | color_base: normal_color}
        
        # Render and send frame to panels
        render_and_update(new_state)
        
        {:noreply, new_state}
    end
  end

  def handle_event(%SpaceMouseEvent{type: :connected, device_info: _device_info}, state) do
    # Device connected - could show a welcome pattern
    Octopus.SpaceMouse.set_led(:on)
    new_state = %State{state | led_state: :on}
    {:noreply, new_state}
  end

  def handle_event(%SpaceMouseEvent{type: :disconnected}, state) do
    # Device disconnected - show disconnection pattern
    new_state = %State{state | led_state: :unknown}
    {:noreply, new_state}
  end

  def handle_event(%SpaceMouseEvent{type: :led, led: led_data}, state) do
    # Track LED state changes
    new_state = %State{state | led_state: led_data.to}
    {:noreply, new_state}
  end

  def handle_event(_other_event, state) do
    # Ignore other event types (audio, proximity, etc.)
    {:noreply, state}
  end

  # Render and update the display
  defp render_and_update(state) do
    # Create a simple visual representation based on SpaceMouse state
    color = hsv_to_rgb(state.color_base.h, state.color_base.s, state.color_base.v)
    
    # Create canvas
    canvas = Canvas.new(state.display_info.width, state.display_info.height)
    
    # Create a pattern that responds to motion and fill the canvas
    canvas_with_pattern = create_motion_pattern(canvas, state.translation, state.rotation, color, state.display_info)
    
    # Send to display
    Octopus.App.update_display(canvas_with_pattern)
  end

  @impl true
  def terminate(_reason, _state) do
    # Clean up: turn off LED and disable SpaceMouse
    Octopus.SpaceMouse.set_led(:off)
    Octopus.SpaceMouse.disable()
    :ok
  end

  # Helper functions for color and pattern generation

  defp round_to_3(value) when is_integer(value), do: "#{value}.000"
  defp round_to_3(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)

  defp hsv_to_rgb(h, s, v) do
    # Convert HSV to RGB (simplified version)
    h_i = div(h, 60)
    f = h / 60.0 - h_i
    p = v * (100 - s) / 100
    q = v * (100 - s * f) / 100
    t = v * (100 - s * (1 - f)) / 100

    {r, g, b} = case h_i do
      0 -> {v, t, p}
      1 -> {q, v, p}
      2 -> {p, v, t}
      3 -> {p, q, v}
      4 -> {t, p, v}
      5 -> {v, p, q}
    end

    {round(r * 255 / 100), round(g * 255 / 100), round(b * 255 / 100)}
  end

  defp create_motion_pattern(canvas, _translation, _rotation, {r, g, b}, _display_info) do
    # Create a simple full-canvas fill to clearly show color changes
    # Since we're focusing on color control, we want the entire display to show the current color
    Canvas.fill(canvas, {r, g, b})
  end

  @impl true
  def config_schema do
    %{}
  end

  @impl true
  def get_config(_state) do
    %{}
  end

  @impl true
  def handle_config(_config, state) do
    {:noreply, state}
  end
end
