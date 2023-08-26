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
      live "/app/:id", AppLive
      live "/", ManagerLive
      live "/playlist/:id", PlaylistLive
      live "/presence", PresenceLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", OctopusWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:octopus, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OctopusWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
