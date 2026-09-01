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

    live_session :default,
      on_mount: {OctopusWeb.Live.Hooks.AssignCurrentPath, :default} do
      live "/sim", PixelsLive
      live "/app/:id", AppLive
      live "/", ManagerLive
      live "/studio", StudioLive
      live "/playlists", PlaylistsLive
      live "/playlist/:id", PlaylistLive
      live "/firmware-info", FirmwareInfoLive
      live "/proximity", ProximityLive
      live "/radar", RadarLive
      live "/radar/debug", RadarDebugLive
      live "/nation", NationLive
    end

    live_session :sim3d,
      root_layout: {OctopusWeb.Layouts, :root_sim3d},
      on_mount: {OctopusWeb.Live.Hooks.AssignCurrentPath, :default} do
      live "/sim3d", Sim3dLive
    end

    live_session :sim3daframe,
      root_layout: {OctopusWeb.Layouts, :root_aframe},
      on_mount: {OctopusWeb.Live.Hooks.AssignCurrentPath, :default} do
      live "/sim3daframe", Sim3dAframeLive
    end
  end

  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through :browser

    live_dashboard "/dashboard", metrics: OctopusWeb.Telemetry
  end
end
