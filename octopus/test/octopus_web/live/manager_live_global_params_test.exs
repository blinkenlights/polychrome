defmodule OctopusWeb.ManagerLiveGlobalParamsTest do
  use OctopusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  # ManagerLive forwards {:param_updated, ...} broadcasts to the
  # GlobalParamsComponent, which is rendered once, nested inside
  # InstallationConsoleComponent. A stale component id here used to log
  # "send_update failed ... does not exist" and silently break UI sync.
  setup do
    # The embedded PixelsLive sim preview does not join under LiveViewTest and
    # is irrelevant here, so mount the console without it.
    previous = Application.get_env(:octopus, :show_sim_preview)
    Application.put_env(:octopus, :show_sim_preview, false)
    on_exit(fn -> Application.put_env(:octopus, :show_sim_preview, previous) end)
    :ok
  end

  test "global param broadcasts reach the nested params component", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    log =
      capture_log(fn ->
        send(view.pid, {:param_updated, :brightness, 42})
        send(view.pid, {:param_updated, :auto_brightness, true})
        # Round-trip so the LiveView has processed both messages and re-rendered.
        _ = render(view)
      end)

    refute log =~ "send_update failed"

    assert has_element?(view, "#global-params-form input[name=brightness][value='42']")
    assert has_element?(view, "#global-params-form #global-auto_brightness[checked]")
  end
end
