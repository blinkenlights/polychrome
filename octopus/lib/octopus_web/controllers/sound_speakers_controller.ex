defmodule OctopusWeb.SoundSpeakersController do
  @moduledoc "Speaker positions for renderers outside the BEAM, see `Octopus.Sound.Speakers`."

  use OctopusWeb, :controller

  def index(conn, _params), do: json(conn, Octopus.Sound.Speakers.describe())
end
