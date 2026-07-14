defmodule Octopus.Hardware.ControllerPortTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware
  alias Octopus.Hardware.Controller

  test "pixie exposes two ports with derived UDP listen ports" do
    pixie = Hardware.fetch!(:pixie)

    assert pixie.ports == 2
    assert pixie.udp_port_base == 1337
    assert Controller.udp_port(pixie, 1) == 1337
    assert Controller.udp_port(pixie, 2) == 1338
  end

  test "nation controllers default to a single port" do
    controller = Hardware.fetch!(:polychrome_01)

    assert controller.ports == 1
    assert Controller.udp_port(controller, 1) == 1337
  end

  test "Pixie network target uses UDP 1337" do
    panels = Octopus.Installation.Pixie.network_config()[:panels]

    assert [[address: "blinkenleds-prototype.local", panel_index: 1, port: 1337]] = panels
  end

  test "Pixie2 network target uses UDP 1338" do
    panels = Octopus.Installation.Pixie2.network_config()[:panels]

    assert [[address: "blinkenleds-prototype.local", panel_index: 1, port: 1338]] = panels
  end

  test "Woodstock network target uses UDP 1338" do
    panels = Octopus.Installation.Woodstock.network_config()[:panels]

    assert [[address: "blinkenleds-prototype.local", panel_index: 1, port: 1338]] = panels
  end
end

