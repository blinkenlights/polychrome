defmodule OctopusWeb.Live.Hooks.AssignCurrentPath do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, fn _params, url, socket ->
        path = url |> URI.parse() |> Map.fetch!(:path)

        {:cont, assign(socket, :current_path, path)}
      end)

    {:cont, assign(socket, current_path: "/")}
  end
end
