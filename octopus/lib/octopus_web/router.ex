defmodule OctopusWeb.Router do
  use OctopusWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {OctopusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OctopusWeb do
    pipe_through :browser

    live_session :default, on_mount: OctopusWeb.PresenceLive do
      live "/sim", PixelsLive
      live "/sim3d", Sim3dLive
      live "/sim3daframe", Sim3dAframeLive
      live "/app/:id", AppLive
      live "/", ManagerLive
      live "/playlist/:id", PlaylistLive
      live "/presence", PresenceLive
      live "/firmware-info", FirmwareInfoLive
      live "/proximity", ProximityLive
      live "/radar", RadarLive
    end
  end

  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through :browser

    live_dashboard "/dashboard", metrics: OctopusWeb.Telemetry
  end
end
