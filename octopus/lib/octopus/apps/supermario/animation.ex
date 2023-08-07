defmodule Octopus.Apps.Supermario.Animation do
  @moduledoc """
  Base module for animations
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.Animation.{GameOver, Intro, MarioDies}

  @type t :: %__MODULE__{
          start_time: Time.t(),
          animation_type: :intro | :mario_dies | :pause | :game_over,
          data: any()
        }
  defstruct [
    :start_time,
    :animation_type,
    :data
  ]

  def new(animation_type, data) do
    # dependended on the animation type initalize more data,

    %Animation{
      start_time: Time.utc_now(),
      animation_type: animation_type,
      data: data
    }
  end

  def draw(%Animation{animation_type: :mario_dies} = animation) do
    MarioDies.draw(animation)
  end

  def draw(%Animation{animation_type: :intro} = animation) do
    Intro.draw(animation)
  end

  def draw(%Animation{animation_type: :game_over} = animation) do
    GameOver.draw(animation)
  end

  def draw(_), do: []
end
