defmodule Octopus.Sound.Speakers do
  @moduledoc """
  Where each sound channel sits in the world, for listening to the ring
  somewhere other than inside it — a binaural renderer on headphones, say.

  Channels count in frame order: channel `c` is the speaker of frame panel
  `c - 1`, because probes and triggers index panels the way the frame lays
  them out. The physical panel behind a frame index is not the same number;
  `Octopus.Radar.PanelMapping` knows the turn and the direction, and this
  module is the one place sound asks it.

  Coordinates are those of `Octopus.Installation.World`: meters, `x` east,
  `y` north, `z` up. The speaker is taken to sit at the panel's inner face.
  """

  alias Octopus.Installation.World
  alias Octopus.Radar.PanelMapping

  @type speaker :: %{
          channel: pos_integer(),
          panel: pos_integer(),
          x: float(),
          y: float(),
          z: float()
        }

  @doc "One speaker per channel, in channel order. Empty unless the ring is circular."
  @spec positions() :: [speaker()]
  def positions, do: positions(World.describe())

  defp positions(%{ring: nil}), do: []

  defp positions(%{ring: %{north_panel: north}, panels: panels}) do
    faces = Map.new(panels, &{&1.panel, &1.inner_face})
    count = length(panels)

    for channel <- 1..count//1 do
      panel = PanelMapping.installation_panel_of_frame(channel - 1, count, north)
      %{x: x, y: y, z: z} = Map.fetch!(faces, panel)
      %{channel: channel, panel: panel, x: x, y: y, z: z}
    end
  end

  @doc """
  The whole description a renderer needs: the ring, a place to stand, the
  speakers. Radii are `nil` and the list is empty when the ring is not circular.
  """
  @spec describe() :: map()
  def describe do
    world = World.describe()

    %{
      ring_radius_m: world.ring && world.ring.radius_m,
      platform_radius_m: world.ring && world.ring.platform_radius_m,
      listener_default: %{x: 0.0, y: 0.0, z: 1.6},
      speakers: positions(world)
    }
  end
end
