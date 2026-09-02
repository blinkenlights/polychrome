defmodule Octopus.Sound.Probes do
  @moduledoc """
  Measuring points in the picture.

  The pixelfun formula answers for every place and moment. The picture asks it
  at every pixel; sound asks it at a handful of points — by default the centre
  of each panel — and uses the answers as a modulation source. Nothing is
  translated from picture to sound: it is the same function, sampled coarsely.

  Values are in `[-1, 1]`, one per panel, in panel order, published on every
  rendered frame.

  **How** a panel becomes one number is a choice, because it decides what a
  listener perceives. The centre pixel is the sharpest and the cheapest; a mean
  over the panel is what the eye actually sees, since a panel is 8 by 8 pixels
  and a wave passes across it rather than landing on one point. The two differ
  most exactly where a colour seam sits: the signed mean cancels there while
  the panel is plainly lit.
  """

  alias Phoenix.PubSub

  @topic "pixel_probes"
  @mode_key {__MODULE__, :mode}

  @modes [
    {:center, "Mittelpixel", "Ein Pixel in der Panelmitte. Am schärfsten und am billigsten."},
    {:mean, "Panelmittel",
     "Mittelwert über alle Pixel des Panels, mit Vorzeichen. Ruhiger; hebt sich dort auf, wo eine Farbnaht durchs Panel läuft."},
    {:brightness, "Panelhelligkeit",
     "Mittlere Helligkeit über alle Pixel, immer positiv. Am nächsten an dem, was man sieht."},
    {:max, "Panelmaximum",
     "Der stärkste Pixel des Panels, mit seinem Vorzeichen. Reagiert, sobald irgendwo etwas hell wird."}
  ]

  @type reading :: %{values: [float()], seconds: float(), at_ms: integer()}

  @doc "Receives `{:pixel_probes, reading}` for every rendered frame."
  def subscribe, do: PubSub.subscribe(Octopus.PubSub, @topic)

  def unsubscribe, do: PubSub.unsubscribe(Octopus.PubSub, @topic)

  def topic, do: @topic

  @doc "The ways a panel can be reduced to one number, with what each means."
  @spec modes() :: [{atom(), String.t(), String.t()}]
  def modes, do: @modes

  @doc "How panels are being measured right now."
  @spec mode() :: atom()
  def mode, do: :persistent_term.get(@mode_key, :center)

  @doc "Changes how panels are measured, for everything that listens."
  @spec set_mode(atom()) :: :ok
  def set_mode(mode) do
    if Enum.any?(@modes, fn {known, _name, _hint} -> known == mode end) do
      :persistent_term.put(@mode_key, mode)
    end

    :ok
  end

  @doc "The readable name of a mode."
  @spec mode_name(atom()) :: String.t()
  def mode_name(mode) do
    Enum.find_value(@modes, to_string(mode), fn {known, name, _hint} ->
      if known == mode, do: name
    end)
  end

  @doc """
  Reduces one panel's pixel values to the single number the mode asks for.
  """
  @spec reduce(atom(), [float()]) :: float()
  def reduce(:mean, values), do: Enum.sum(values) / length(values)

  def reduce(:brightness, values),
    do: values |> Enum.map(&abs/1) |> Enum.sum() |> Kernel./(length(values))

  def reduce(:max, values), do: Enum.max_by(values, &abs/1)
  def reduce(_center, values), do: hd(values)

  @doc """
  Publishes one frame of probe values.

  `at_ms` should be the frame's **scheduled** time, not the moment the frame
  finished rendering. Rendering takes a varying number of milliseconds, and a
  listener that places events between two readings would turn that variance
  into audible stumble. The render loop knows its own grid; it is the honest
  clock here.

  Silently does nothing when PubSub is not running, so a renderer in a bare
  test process stays unaffected.
  """
  @spec broadcast([float()], number(), integer() | nil) :: :ok
  def broadcast(values, seconds, at_ms \\ nil) when is_list(values) do
    if Process.whereis(Octopus.PubSub) do
      reading = %{
        values: values,
        seconds: seconds,
        at_ms: at_ms || Octopus.Sound.Time.now()
      }

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
