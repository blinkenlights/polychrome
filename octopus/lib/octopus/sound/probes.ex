defmodule Octopus.Sound.Probes do
  @moduledoc """
  Measuring points in the picture.

  The pixelfun formula answers for every place and moment. The picture asks it
  at every pixel; sound asks it at a handful of points — by default the centre
  of each panel — and uses the answers as a modulation source. Nothing is
  translated from picture to sound: it is the same function, sampled coarsely.

  Values are in `[-1, 1]`, one per panel, in panel order, published on every
  rendered frame.
  """

  alias Phoenix.PubSub

  @topic "pixel_probes"

  @type reading :: %{values: [float()], seconds: float(), at_ms: integer()}

  @doc "Receives `{:pixel_probes, reading}` for every rendered frame."
  def subscribe, do: PubSub.subscribe(Octopus.PubSub, @topic)

  def unsubscribe, do: PubSub.unsubscribe(Octopus.PubSub, @topic)

  def topic, do: @topic

  @doc """
  Publishes one frame of probe values. Silently does nothing when PubSub is
  not running, so a renderer in a bare test process stays unaffected.
  """
  @spec broadcast([float()], number()) :: :ok
  def broadcast(values, seconds) when is_list(values) do
    if Process.whereis(Octopus.PubSub) do
      reading = %{values: values, seconds: seconds, at_ms: Octopus.Sound.Time.now()}
      PubSub.broadcast(Octopus.PubSub, @topic, {:pixel_probes, reading})
    end

    :ok
  end

  @doc """
  Index of the pixel at the centre of a panel, for the row-major pixel lists
  the installation hands out.
  """
  @spec center_pixel_index() :: non_neg_integer()
  def center_pixel_index do
    {width, height} = Octopus.Installation.panel_layout()
    div(height, 2) * width + div(width, 2)
  end
end
