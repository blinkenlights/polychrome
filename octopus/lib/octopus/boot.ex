defmodule Octopus.Boot do
  @moduledoc """
  Optional start-up helpers driven by environment / application config.

  Set `BOOT_APP` (or `OCTOPUS_BOOT_APP`) to an app module short name
  (`GravityMask`) or full module (`Octopus.Apps.GravityMask`). Optional
  `BOOT_APP_MODE` selects a mode id when the app exposes `mode_config/1`.
  """

  require Logger

  alias Octopus.InstallationTransport

  @doc """
  Starts the app configured via `:boot_app` / `:boot_app_mode` application env.

  Returns `:ok` when nothing is configured, otherwise the result of starting.
  """
  @spec start_configured_app() :: :ok | {:ok, String.t() | nil} | {:error, term()}
  def start_configured_app do
    case Application.get_env(:octopus, :boot_app) do
      name when is_binary(name) and name != "" ->
        mode = Application.get_env(:octopus, :boot_app_mode)
        start_app(name, mode)

      _ ->
        :ok
    end
  end

  @doc """
  Resolves and starts `name` (optionally with `mode_id`) via InstallationTransport
  so the manager now-playing UI (including tweakables) is populated immediately.
  """
  @spec start_app(String.t(), String.t() | nil) :: {:ok, String.t() | nil} | {:error, term()}
  def start_app(name, mode_id \\ nil) when is_binary(name) do
    with {:ok, module} <- resolve_module(name),
         mode_id <- resolve_mode_id(module, mode_id),
         :ok <- play_now_immediate(module, mode_id) do
      app_id = now_playing_app_id()

      Logger.info(
        "[boot] started #{inspect(module)} mode=#{mode_id}" <>
          if(app_id, do: " as #{app_id}", else: "")
      )

      {:ok, app_id}
    else
      {:error, reason} = error ->
        Logger.warning("[boot] could not start #{name}: #{inspect(reason)}")
        error
    end
  end

  @doc false
  @spec resolve_module(String.t()) :: {:ok, module()} | {:error, :not_found}
  def resolve_module(name) when is_binary(name) do
    module =
      if String.contains?(name, ".") do
        Module.concat(String.split(name, "."))
      else
        Module.concat([Octopus.Apps, name])
      end

    cond do
      not Code.ensure_loaded?(module) ->
        {:error, :not_found}

      module not in Octopus.AppSupervisor.available_apps() ->
        {:error, :not_found}

      true ->
        {:ok, module}
    end
  end

  # Skip the mixer fade so boot completes with live_entry / now_playing set
  # before the web UI can mount.
  defp play_now_immediate(module, mode_id) do
    prev = InstallationTransport.get_state().transition_duration_seconds
    InstallationTransport.set_transition_duration(0)

    try do
      InstallationTransport.play_now(module, mode_id)
    after
      InstallationTransport.set_transition_duration(prev)
    end
  end

  defp now_playing_app_id do
    case InstallationTransport.get_state().now_playing do
      %{app_id: app_id} when is_binary(app_id) -> app_id
      _ -> nil
    end
  end

  defp resolve_mode_id(module, mode_id) do
    cond do
      is_binary(mode_id) and mode_id != "" ->
        mode_id

      true ->
        default_mode_id(module) || "default"
    end
  end

  defp default_mode_id(module) do
    if function_exported?(module, :list_modes, 0) do
      case module.list_modes() do
        [%{id: id} | _] when is_binary(id) -> id
        _ -> nil
      end
    else
      nil
    end
  end
end
