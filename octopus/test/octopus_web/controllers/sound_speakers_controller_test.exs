defmodule OctopusWeb.SoundSpeakersControllerTest do
  # Swaps the installation in the application env.
  use OctopusWeb.ConnCase, async: false

  setup do
    prev = Application.fetch_env!(:octopus, :installation)
    Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)
    on_exit(fn -> Application.put_env(:octopus, :installation, prev) end)
    :ok
  end

  test "GET /api/sound/speakers describes the ring as JSON", %{conn: conn} do
    body = conn |> get(~p"/api/sound/speakers") |> json_response(200)

    assert %{
             "ring_radius_m" => 10.0,
             "listener_default" => %{"x" => _, "y" => _, "z" => _},
             "speakers" => [%{"channel" => 1, "panel" => _, "x" => _, "y" => _, "z" => _} | _]
           } = body

    assert length(body["speakers"]) == 12
  end
end
