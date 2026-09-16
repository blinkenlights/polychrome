defmodule Octopus.Sound.SpeakersTest do
  # Swaps the installation in the application env.
  use ExUnit.Case, async: false

  alias Octopus.Installation
  alias Octopus.Installation.Nation2026
  alias Octopus.Radar.PanelMapping
  alias Octopus.Sound.Speakers

  setup do
    prev = Application.fetch_env!(:octopus, :installation)
    Application.put_env(:octopus, :installation, Nation2026)
    on_exit(fn -> Application.put_env(:octopus, :installation, prev) end)
    :ok
  end

  test "one speaker per channel, in channel order" do
    speakers = Speakers.positions()

    assert Enum.map(speakers, & &1.channel) == Enum.to_list(1..Installation.num_panels())
  end

  test "every speaker sits on the ring, at the panel's face" do
    radius = Installation.ring_radius_m()

    for %{x: x, y: y} <- Speakers.positions() do
      assert_in_delta :math.sqrt(x * x + y * y), radius, 1.0e-6
    end
  end

  test "each physical panel carries exactly one channel" do
    panels = Enum.map(Speakers.positions(), & &1.panel)

    assert Enum.sort(panels) == Enum.to_list(1..Installation.num_panels())
  end

  test "channels count in frame order, placed where the frame panel physically is" do
    count = Installation.num_panels()
    north = Installation.north_panel()

    for %{channel: channel, panel: panel} <- Speakers.positions() do
      assert panel == PanelMapping.installation_panel_of_frame(channel - 1, count, north)
    end
  end

  test "the physical north panel sits due north" do
    north = Installation.north_panel()
    %{x: x, y: y} = Enum.find(Speakers.positions(), &(&1.panel == north))

    assert_in_delta x, 0.0, 1.0e-6
    assert y > 0
  end

  test "a linear installation has no speakers to place" do
    Application.put_env(:octopus, :installation, Octopus.Installation.Pixie)

    assert Speakers.positions() == []
    assert %{ring_radius_m: nil, speakers: []} = Speakers.describe()
  end
end
