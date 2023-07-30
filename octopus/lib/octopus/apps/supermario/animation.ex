defmodule Octopus.Apps.Supermario.Animation do
  @moduledoc """
  Base module for animations
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.Animation.MarioDies

  @type t :: %__MODULE__{
          start_time: Time.t(),
          animation_type: :intro | :mario_dies | :pause,
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

  # def init_animation(:intro) do
  #   # TODO
  # end

  # def init_animation(:pause) do
  #   # TODO
  # end

  # def init_animation(:mario_dies) do
  #   MarioDies.init_animation()
  # end

  def draw(%Animation{animation_type: :mario_dies} = animation) do
    MarioDies.draw(animation)
  end

  def draw(%Animation{} = animation) do
    require IEx
    IEx.pry()
  end
end

# mario_dies animation ...
#   game draw
#     mario position
#       colour rotation
#       radial boom effect from mario position

# intro animation
#   Webpanimation
#     without handle infos etc .
