defmodule Octopus.Apps.Collective.Animation do
  @moduledoc """
  Behaviour for Collective animations.

  An animation is a pure-ish renderer: given the current crowd (radar-track-shaped
  person maps) and a per-frame context, it draws onto a `Octopus.Canvas` and
  returns its own evolving state. The host app (`Octopus.Apps.Collective`) owns the
  tick loop, the crowd source and `update_display/1`.
  """

  alias Octopus.Canvas

  @typedoc "Radar-track-shaped person: meters / m/s, origin at ring center."
  @type person :: %{id: pos_integer(), x: float(), y: float(), vx: float(), vy: float()}

  @typedoc """
  Per-frame context.

    * `:dt` — seconds since last frame
    * `:sensitivity` — user-tunable gain (animation-specific meaning)
    * `:display_info` — `Octopus.App.get_display_info/0` result (width/height/...)
  """
  @type ctx :: %{
          dt: float(),
          sensitivity: float(),
          display_info: map()
        }

  @doc "Human-readable name of the animation."
  @callback name() :: String.t()

  @doc "Builds the initial animation state from the display info."
  @callback init(display_info :: map()) :: map()

  @doc "Renders one frame; returns the updated canvas and animation state."
  @callback render(Canvas.t(), [person()], ctx(), state :: map()) :: {Canvas.t(), map()}
end
