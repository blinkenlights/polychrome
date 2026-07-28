defmodule OctopusWeb.LaunchpadLive do
  use OctopusWeb, :live_view

  import Phoenix.LiveView, only: [connected?: 1]

  alias Octopus.Installation
  alias Octopus.Outputs.LaunchpadMini
  alias Octopus.Params.Launchpad, as: LaunchpadParams
  alias OctopusWeb.PixelsLive

  def mount(_params, _session, socket) do
    compatible? = compatible_installation?()

    socket =
      socket
      |> assign(
        compatible?: compatible?,
        num_panels: Installation.num_panels(),
        panel_layout: Installation.panel_layout(),
        brightness_min: LaunchpadParams.brightness_min(),
        brightness_max: LaunchpadParams.brightness_max(),
        config: LaunchpadParams.config(),
        status: :not_running
      )

    socket =
      if connected?(socket) and compatible? do
        LaunchpadParams.subscribe()
        connect_output(socket)
      else
        socket
      end

    {:ok, socket}
  end

  def terminate(_reason, socket) do
    if socket.assigns[:output_started?] do
      case GenServer.whereis(LaunchpadMini) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    end

    :ok
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex flex-col items-center gap-6 p-6">
      <h1 class="text-xl font-semibold">Launchpad Mini MK3</h1>

      <div :if={!@compatible?} class="alert alert-warning max-w-md">
        <span>
          Nur für 1x8x8-Installationen verfügbar. Aktuelle Installation: {@num_panels}x{elem(
            @panel_layout,
            0
          )}x{elem(@panel_layout, 1)}.
        </span>
      </div>

      <div
        :if={@compatible?}
        class="flex flex-col md:flex-row gap-6 items-start w-full max-w-3xl justify-center"
      >
        <div class="w-72 h-72 md:w-96 md:h-96 bg-black rounded-lg overflow-hidden shrink-0">
          {live_render(@socket, PixelsLive, id: "launchpad-preview", session: %{"embedded" => true})}
        </div>

        <div class="card bg-base-100 shadow p-4 w-full md:w-80 space-y-4">
          <div>
            <div class="text-sm font-medium mb-1">Verbindung</div>
            <span class={["badge", status_badge_class(@status)]}>{status_label(@status)}</span>
          </div>

          <form phx-change="update-config" class="space-y-1">
            <label class="flex flex-col gap-1">
              <span class="text-xs uppercase tracking-wide opacity-60">Helligkeit</span>
              <input
                type="range"
                name="brightness"
                min={@brightness_min}
                max={@brightness_max}
                value={@config.brightness}
                class="range range-primary range-sm"
              />
              <span class="text-xs tabular-nums opacity-70">{@config.brightness}</span>
            </label>
          </form>

          <div class="divider my-1" />

          <div class="opacity-50 text-sm">
            <div class="font-medium mb-1">Button-Mapping</div>
            <div>Geplant für eine spätere Ausbaustufe.</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("update-config", %{"brightness" => value}, socket) do
    {brightness, _} = Integer.parse(value)
    LaunchpadParams.update_config(%{brightness: brightness})

    {:noreply, assign(socket, config: %{socket.assigns.config | brightness: brightness})}
  end

  def handle_info({:param_updated, :brightness, value}, socket) do
    {:noreply, assign(socket, config: %{socket.assigns.config | brightness: value})}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply, assign(socket, status: {:error, reason}, output_started?: false)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp compatible_installation? do
    Installation.num_panels() == 1 and Installation.panel_layout() == {8, 8}
  end

  defp connect_output(socket) do
    case LaunchpadMini.start_link() do
      {:ok, pid} ->
        Process.monitor(pid)
        assign(socket, status: :connected, output_started?: true)

      {:error, {:already_started, pid}} ->
        Process.monitor(pid)
        assign(socket, status: :connected, output_started?: false)

      {:error, reason} ->
        assign(socket, status: {:error, reason}, output_started?: false)
    end
  end

  defp status_label(:connected), do: "Verbunden"
  defp status_label(:not_running), do: "Nicht aktiv"
  defp status_label({:error, :not_found}), do: "Gerät nicht gefunden"
  defp status_label({:error, reason}), do: "Fehler: #{inspect(reason)}"

  defp status_badge_class(:connected), do: "badge-success"
  defp status_badge_class(:not_running), do: "badge-ghost"
  defp status_badge_class({:error, _reason}), do: "badge-error"
end
