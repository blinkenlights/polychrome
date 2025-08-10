# SpaceMouse Integration for Octopus

This subsystem provides SpaceMouse support for Octopus applications, allowing apps to receive and respond to 6DOF (six degrees of freedom) motion input, button presses, and control device features like the LED.

## Overview

The SpaceMouse subsystem consists of several components:

- **`Octopus.SpaceMouse`** - Main public API for apps
- **`Octopus.SpaceMouse.Adapter`** - Event bridge between SpaceMouse library and Octopus events
- **`Octopus.Events.Event.SpaceMouse`** - Event structs for SpaceMouse data
- **Events.Router integration** - Routes SpaceMouse events to selected apps

## Architecture

```
SpaceMouse Device
       ↓
SpaceMouse Library (External)
       ↓
Octopus.SpaceMouse.Adapter
       ↓
Octopus.Events.Router
       ↓
Selected App
```

## Usage for App Developers

### 1. Enable SpaceMouse Support

In your app's `init/1` function:

```elixir
def init(config) do
  case Octopus.SpaceMouse.enable() do
    :ok ->
      # Optional: Turn on LED to show app is active
      Octopus.SpaceMouse.set_led(:on)
      {:ok, initial_state}
    
    {:error, reason} ->
      {:stop, {:spacemouse_error, reason}}
  end
end
```

### 2. Handle SpaceMouse Events

Add event handlers in your app:

```elixir
# Handle 6DOF motion events
def handle_info({:event, %SpaceMouseEvent{type: :motion, motion: motion}}, state) do
  # motion contains: %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}
  # Values are normalized to -1.0 to +1.0 range
  
  # Example: Use translation for camera movement
  new_camera_pos = update_camera(state.camera, motion.x, motion.y, motion.z)
  
  # Example: Use rotation for object rotation
  new_object_rot = update_rotation(state.object, motion.rx, motion.ry, motion.rz)
  
  {:noreply, %{state | camera: new_camera_pos, object: new_object_rot}}
end

# Handle button events
def handle_info({:event, %SpaceMouseEvent{type: :button, button: button}}, state) do
  case {button.id, button.state} do
    {1, :pressed} ->
      # Button 1 pressed - maybe reset view
      {:noreply, reset_view(state)}
    
    {1, :released} ->
      # Button 1 released
      {:noreply, state}
    
    {2, :pressed} ->
      # Button 2 pressed - maybe toggle mode
      {:noreply, toggle_mode(state)}
    
    _ ->
      {:noreply, state}
  end
end

# Handle device connection/disconnection
def handle_info({:event, %SpaceMouseEvent{type: :connected, device_info: info}}, state) do
  # Device connected
  Octopus.SpaceMouse.set_led(:on)
  {:noreply, state}
end

def handle_info({:event, %SpaceMouseEvent{type: :disconnected}}, state) do
  # Device disconnected
  {:noreply, state}
end
```

### 3. Control the LED

```elixir
# Turn LED on
Octopus.SpaceMouse.set_led(:on)

# Turn LED off
Octopus.SpaceMouse.set_led(:off)

# Check current LED state
current_state = Octopus.SpaceMouse.get_led_state()  # :on, :off, or :unknown
```

### 4. Clean Up

In your app's `terminate/2` function:

```elixir
def terminate(_reason, _state) do
  # Turn off LED and disable SpaceMouse support
  Octopus.SpaceMouse.set_led(:off)
  Octopus.SpaceMouse.disable()
  :ok
end
```

## Event Types

### Motion Events

```elixir
%SpaceMouseEvent{
  type: :motion,
  motion: %{
    x: -0.351,   # Translation X (-1.0 to +1.0)
    y: 0.191,    # Translation Y (-1.0 to +1.0) 
    z: -0.571,   # Translation Z (-1.0 to +1.0)
    rx: 0.129,   # Rotation X (-1.0 to +1.0)
    ry: -0.254,  # Rotation Y (-1.0 to +1.0)
    rz: 0.446    # Rotation Z (-1.0 to +1.0)
  }
}
```

### Button Events

```elixir
%SpaceMouseEvent{
  type: :button,
  button: %{
    id: 1,              # Button ID (1, 2, etc.)
    state: :pressed     # :pressed or :released
  }
}
```

### LED Events

```elixir
%SpaceMouseEvent{
  type: :led,
  led: %{
    from: :off,                    # Previous state
    to: :on,                       # New state  
    timestamp: 1640995200000       # When it changed
  }
}
```

### Connection Events

```elixir
%SpaceMouseEvent{
  type: :connected,  # or :disconnected
  device_info: %{
    vendor_id: 0x256F,
    product_id: 0xC635,
    name: "SpaceMouse Compact"
  }
}
```

## Utility Functions

The `SpaceMouseEvent` module provides utility functions:

```elixir
# Get overall motion magnitude
magnitude = SpaceMouseEvent.motion_magnitude(event)

# Get translation magnitude only
trans_mag = SpaceMouseEvent.translation_magnitude(event)

# Get rotation magnitude only  
rot_mag = SpaceMouseEvent.rotation_magnitude(event)
```

## API Reference

### Octopus.SpaceMouse

- `enable/0` - Enable SpaceMouse support
- `disable/0` - Disable SpaceMouse support  
- `set_led/1` - Set LED state (`:on` or `:off`)
- `get_led_state/0` - Get current LED state
- `enabled?/0` - Check if support is enabled
- `get_device_info/0` - Get connected device information
- `subscribe/0` - Subscribe to debug events

## Example Apps

See `Octopus.Apps.SpaceMouseDemo` for a complete example that demonstrates:

- Enabling/disabling SpaceMouse support
- Handling all event types
- LED control
- Creating visual feedback from motion
- Proper cleanup

## Error Handling

Common errors and how to handle them:

```elixir
case Octopus.SpaceMouse.enable() do
  :ok -> 
    # Success
    
  {:error, :already_enabled} ->
    # Already enabled by another app
    
  {:error, :no_device} ->
    # No SpaceMouse connected
    
  {:error, :platform_not_supported} ->
    # Platform doesn't support SpaceMouse
end
```

## Platform Support

Currently supports:
- **macOS** - Full support via IOKit HID Manager
- **Linux** - Planned (will use direct libusb)
- **Windows** - Planned (will use Windows HID API)

## Performance Notes

- Motion events can arrive at ~375 Hz maximum
- Event latency is typically <5ms
- CPU usage is <5% during active use
- Memory footprint is ~2MB total

## Debugging

Subscribe to adapter events for debugging:

```elixir
Octopus.SpaceMouse.subscribe()

# You'll receive messages like:
# {:spacemouse_adapter, {:motion, motion_data}}
# {:spacemouse_adapter, {:button, button_data}}
# {:spacemouse_adapter, {:connected, device_info}}
```
