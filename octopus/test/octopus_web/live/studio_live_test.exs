defmodule OctopusWeb.StudioLiveTest do
  use OctopusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Octopus.Installation
  alias Octopus.Sound.Probes

  setup do
    # The embedded sim preview does not join under LiveViewTest.
    previous = Application.get_env(:octopus, :show_sim_preview)
    Application.put_env(:octopus, :show_sim_preview, false)
    on_exit(fn -> Application.put_env(:octopus, :show_sim_preview, previous) end)
    :ok
  end

  test "renders with the sound stack switched off", %{conn: conn} do
    # Test config leaves Octopus.Sound disabled, so this also covers the case
    # of a machine without any audio: the page has to work regardless.
    {:ok, _view, html} = live(conn, ~p"/studio")

    assert html =~ "Probes"
    assert html =~ "Ring-Chase"
    assert html =~ "kein Klang"
  end

  test "shows one column per panel, under the strip", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/studio")
    html = render(view)

    for panel <- 1..Installation.num_panels() do
      assert html =~ ">#{panel}</span>"
    end

    # Meter and probe bar share the panel's column, so they line up with it.
    assert html =~ "bg-info transition-[width]"
  end

  test "picks up probe readings from a rendering scene", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/studio")

    values = List.duplicate(0.0, Installation.num_panels() - 1) ++ [0.75]
    Probes.broadcast(values, 1.0)

    # The bar grows upwards from the middle for a positive reading.
    assert render(view) =~ "bottom: 50%; height: 37.5%"
  end

  test "a played note lights the meter of its panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/studio")

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "sound_notes",
      {:sound_note, %{channel: 1, velocity: 0.8, note: 60, duration_ms: 100, at_ms: 0}}
    )

    assert render(view) =~ "width: 80%"
  end

  test "reports no scene when nothing is on the wall", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/studio")

    assert html =~ "Auf der Wand läuft gerade kein Pixel Fun"
  end
end
