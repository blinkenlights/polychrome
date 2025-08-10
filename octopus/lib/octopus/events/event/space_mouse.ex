defmodule Octopus.Events.Event.SpaceMouse do
  @moduledoc """
  Domain event for SpaceMouse input in the Octopus system.

  This represents SpaceMouse events in a clean, domain-focused format,
  abstracted from the underlying SpaceMouse driver library.

  Event Types:
  - Motion events: 6DOF (six degrees of freedom) movement data
  - Button events: Press/release events for device buttons
  - LED events: LED state change notifications
  - Connection events: Device connection/disconnection notifications
  """

  defstruct [:type, :motion, :button, :led, :device_info]

  @type motion_data :: %{
          x: float(),
          y: float(),
          z: float(),
          rx: float(),
          ry: float(),
          rz: float()
        }

  @type button_data :: %{
          id: pos_integer(),
          state: :pressed | :released
        }

  @type led_data :: %{
          from: :on | :off | :unknown,
          to: :on | :off,
          timestamp: integer()
        }

  @type device_info :: %{
          vendor_id: integer(),
          product_id: integer(),
          name: String.t()
        }

  @type t ::
          %__MODULE__{
            # Motion events (6DOF movement)
            type: :motion,
            motion: motion_data(),
            button: nil,
            led: nil,
            device_info: nil
          }
          | %__MODULE__{
              # Button events
              type: :button,
              motion: nil,
              button: button_data(),
              led: nil,
              device_info: nil
            }
          | %__MODULE__{
              # LED state change events
              type: :led,
              motion: nil,
              button: nil,
              led: led_data(),
              device_info: nil
            }
          | %__MODULE__{
              # Device connection/disconnection events
              type: :connected | :disconnected,
              motion: nil,
              button: nil,
              led: nil,
              device_info: device_info()
            }

  @doc """
  Validates a SpaceMouse event structure.
  """
  def validate(%__MODULE__{type: :motion, motion: motion}) when is_map(motion) do
    required_keys = [:x, :y, :z, :rx, :ry, :rz]

    if Enum.all?(required_keys, &Map.has_key?(motion, &1)) and
         Enum.all?(Map.values(motion), &is_number/1) do
      :ok
    else
      {:error, :invalid_motion_data}
    end
  end

  def validate(%__MODULE__{type: :button, button: button}) when is_map(button) do
    case button do
      %{id: id, state: state}
      when is_integer(id) and id > 0 and state in [:pressed, :released] ->
        :ok

      _ ->
        {:error, :invalid_button_data}
    end
  end

  def validate(%__MODULE__{type: :led, led: led}) when is_map(led) do
    case led do
      %{from: from, to: to, timestamp: timestamp}
      when from in [:on, :off, :unknown] and to in [:on, :off] and is_integer(timestamp) ->
        :ok

      _ ->
        {:error, :invalid_led_data}
    end
  end

  def validate(%__MODULE__{type: type, device_info: device_info})
      when type in [:connected, :disconnected] and is_map(device_info) do
    case device_info do
      %{vendor_id: vid, product_id: pid, name: name}
      when is_integer(vid) and is_integer(pid) and is_binary(name) ->
        :ok

      _ ->
        {:error, :invalid_device_info}
    end
  end

  def validate(_), do: {:error, :invalid_spacemouse_event}

  @doc """
  Creates a motion event from 6DOF motion data.
  """
  def motion(x, y, z, rx, ry, rz) when is_number(x) and is_number(y) and is_number(z) and
                                        is_number(rx) and is_number(ry) and is_number(rz) do
    %__MODULE__{
      type: :motion,
      motion: %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}
    }
  end

  @doc """
  Creates a button event.
  """
  def button(id, state) when is_integer(id) and id > 0 and state in [:pressed, :released] do
    %__MODULE__{
      type: :button,
      button: %{id: id, state: state}
    }
  end

  @doc """
  Creates an LED state change event.
  """
  def led(from, to, timestamp \\ System.monotonic_time(:millisecond))
      when from in [:on, :off, :unknown] and to in [:on, :off] and is_integer(timestamp) do
    %__MODULE__{
      type: :led,
      led: %{from: from, to: to, timestamp: timestamp}
    }
  end

  @doc """
  Creates a device connection event.
  """
  def connected(vendor_id, product_id, name)
      when is_integer(vendor_id) and is_integer(product_id) and is_binary(name) do
    %__MODULE__{
      type: :connected,
      device_info: %{vendor_id: vendor_id, product_id: product_id, name: name}
    }
  end

  @doc """
  Creates a device disconnection event.
  """
  def disconnected(vendor_id, product_id, name)
      when is_integer(vendor_id) and is_integer(product_id) and is_binary(name) do
    %__MODULE__{
      type: :disconnected,
      device_info: %{vendor_id: vendor_id, product_id: product_id, name: name}
    }
  end

  @doc """
  Returns the magnitude of motion for motion events.
  Useful for determining the intensity of movement.
  """
  def motion_magnitude(%__MODULE__{type: :motion, motion: motion}) do
    %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz} = motion
    :math.sqrt(x * x + y * y + z * z + rx * rx + ry * ry + rz * rz)
  end

  def motion_magnitude(_), do: 0.0

  @doc """
  Returns the translation magnitude (X, Y, Z) for motion events.
  """
  def translation_magnitude(%__MODULE__{type: :motion, motion: motion}) do
    %{x: x, y: y, z: z} = motion
    :math.sqrt(x * x + y * y + z * z)
  end

  def translation_magnitude(_), do: 0.0

  @doc """
  Returns the rotation magnitude (RX, RY, RZ) for motion events.
  """
  def rotation_magnitude(%__MODULE__{type: :motion, motion: motion}) do
    %{rx: rx, ry: ry, rz: rz} = motion
    :math.sqrt(rx * rx + ry * ry + rz * rz)
  end

  def rotation_magnitude(_), do: 0.0
end
