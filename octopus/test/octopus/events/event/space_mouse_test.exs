defmodule Octopus.Events.Event.SpaceMouseTest do
  use ExUnit.Case, async: true

  alias Octopus.Events.Event.SpaceMouse, as: SpaceMouseEvent

  describe "motion events" do
    test "motion/6 creates valid motion event" do
      event = SpaceMouseEvent.motion(0.5, -0.3, 0.8, 0.1, -0.9, 0.4)
      
      assert event.type == :motion
      assert event.motion.x == 0.5
      assert event.motion.y == -0.3
      assert event.motion.z == 0.8
      assert event.motion.rx == 0.1
      assert event.motion.ry == -0.9
      assert event.motion.rz == 0.4
    end

    test "validates motion event correctly" do
      valid_event = SpaceMouseEvent.motion(0.5, -0.3, 0.8, 0.1, -0.9, 0.4)
      assert SpaceMouseEvent.validate(valid_event) == :ok
    end

    test "motion_magnitude calculates correctly" do
      event = SpaceMouseEvent.motion(0.3, 0.4, 0.0, 0.0, 0.0, 0.0)
      magnitude = SpaceMouseEvent.motion_magnitude(event)
      assert_in_delta magnitude, 0.5, 0.001
    end

    test "translation_magnitude calculates correctly" do
      event = SpaceMouseEvent.motion(0.3, 0.4, 0.0, 1.0, 1.0, 1.0)
      magnitude = SpaceMouseEvent.translation_magnitude(event)
      assert_in_delta magnitude, 0.5, 0.001
    end

    test "rotation_magnitude calculates correctly" do
      event = SpaceMouseEvent.motion(1.0, 1.0, 1.0, 0.3, 0.4, 0.0)
      magnitude = SpaceMouseEvent.rotation_magnitude(event)
      assert_in_delta magnitude, 0.5, 0.001
    end
  end

  describe "button events" do
    test "button/2 creates valid button event" do
      event = SpaceMouseEvent.button(1, :pressed)
      
      assert event.type == :button
      assert event.button.id == 1
      assert event.button.state == :pressed
    end

    test "validates button event correctly" do
      valid_event = SpaceMouseEvent.button(2, :released)
      assert SpaceMouseEvent.validate(valid_event) == :ok
    end

    test "rejects invalid button id" do
      invalid_event = %SpaceMouseEvent{
        type: :button,
        button: %{id: 0, state: :pressed}
      }
      assert SpaceMouseEvent.validate(invalid_event) == {:error, :invalid_button_data}
    end
  end

  describe "LED events" do
    test "led/3 creates valid LED event" do
      timestamp = System.monotonic_time(:millisecond)
      event = SpaceMouseEvent.led(:off, :on, timestamp)
      
      assert event.type == :led
      assert event.led.from == :off
      assert event.led.to == :on
      assert event.led.timestamp == timestamp
    end

    test "led/2 creates LED event with current timestamp" do
      event = SpaceMouseEvent.led(:on, :off)
      
      assert event.type == :led
      assert event.led.from == :on
      assert event.led.to == :off
      assert is_integer(event.led.timestamp)
    end

    test "validates LED event correctly" do
      event = SpaceMouseEvent.led(:unknown, :on)
      assert SpaceMouseEvent.validate(event) == :ok
    end
  end

  describe "connection events" do
    test "connected/3 creates valid connection event" do
      event = SpaceMouseEvent.connected(0x256F, 0xC635, "SpaceMouse Compact")
      
      assert event.type == :connected
      assert event.device_info.vendor_id == 0x256F
      assert event.device_info.product_id == 0xC635
      assert event.device_info.name == "SpaceMouse Compact"
    end

    test "disconnected/3 creates valid disconnection event" do
      event = SpaceMouseEvent.disconnected(0x256F, 0xC635, "SpaceMouse Compact")
      
      assert event.type == :disconnected
      assert event.device_info.vendor_id == 0x256F
      assert event.device_info.product_id == 0xC635
      assert event.device_info.name == "SpaceMouse Compact"
    end

    test "validates connection event correctly" do
      event = SpaceMouseEvent.connected(0x256F, 0xC635, "Test Device")
      assert SpaceMouseEvent.validate(event) == :ok
    end
  end

  describe "validation" do
    test "rejects invalid event types" do
      invalid_event = %SpaceMouseEvent{type: :invalid}
      assert SpaceMouseEvent.validate(invalid_event) == {:error, :invalid_spacemouse_event}
    end

    test "rejects motion event with missing keys" do
      invalid_event = %SpaceMouseEvent{
        type: :motion,
        motion: %{x: 1.0, y: 2.0}  # Missing z, rx, ry, rz
      }
      assert SpaceMouseEvent.validate(invalid_event) == {:error, :invalid_motion_data}
    end

    test "rejects motion event with non-numeric values" do
      invalid_event = %SpaceMouseEvent{
        type: :motion,
        motion: %{x: "invalid", y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0}
      }
      assert SpaceMouseEvent.validate(invalid_event) == {:error, :invalid_motion_data}
    end
  end

  describe "utility functions for non-motion events" do
    test "motion_magnitude returns 0.0 for non-motion events" do
      button_event = SpaceMouseEvent.button(1, :pressed)
      assert SpaceMouseEvent.motion_magnitude(button_event) == 0.0
    end

    test "translation_magnitude returns 0.0 for non-motion events" do
      led_event = SpaceMouseEvent.led(:on, :off)
      assert SpaceMouseEvent.translation_magnitude(led_event) == 0.0
    end

    test "rotation_magnitude returns 0.0 for non-motion events" do
      connection_event = SpaceMouseEvent.connected(0x256F, 0xC635, "Test")
      assert SpaceMouseEvent.rotation_magnitude(connection_event) == 0.0
    end
  end
end
