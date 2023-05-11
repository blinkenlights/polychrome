defmodule OctopusWeb.SimulatorLive do
  use OctopusWeb, :live_view
  use OctopusWeb.PixelsComponent

  alias OctopusWeb.PixelsComponent
  alias Octopus.Mixer
  alias Octopus.Protobuf.InputEvent

  def mount(_params, _session, socket) do
    socket = PixelsComponent.mount(socket)
    {:ok, socket, temporary_assigns: PixelsComponent.temporary_assigns()}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black" phx-window-keydown="keydown-event">
      <.pixels id="pixels" pixel_layout={@pixel_layout} />
    </div>
    """
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> push_config(config)}
  end

  def handle_event("keydown-event", %{"key" => key}, socket)
      when key in ~w(0 1 2 3 4 5 6 7 8 9) do
    %InputEvent{
      type: :BUTTON,
      value: String.to_integer(key)
    }
    |> Mixer.handle_input()

    {:noreply, socket}
  end

  def handle_event("keydown-event", %{"key" => _other_key}, socket) do
    {:noreply, socket}
  end
end
