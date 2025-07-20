defmodule Octopus.Apps.Eventphone do
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  alias Octopus.WebP
  use Octopus.App, category: :test

  def name, do: "Eventphone"

  def compatible?() do
    # Only compatible with 10-panel installations like Nation2024
    installation_info = Octopus.App.get_installation_info()
    installation_info.panel_count == 10
  end

  def config_schema do
    %{
      image: {"Static Image", :string, %{default: "polychrome_eventphone"}}
    }
  end

  def get_config(%{image: image}) do
    %{image: image}
  end

  def app_init(%{image: image}) do
    # Load image to determine appropriate layout
    loaded_image = WebP.load(image)

    # Configure layout based on image width (was Canvas.to_frame(drop: image.width > 80))
    layout =
      if loaded_image && loaded_image.width > 80, do: :gapped_panels, else: :adjacent_panels

    Octopus.App.configure_display(layout: layout)

    send(self(), :display)
    {:ok, %{image: image}}
  end

  def handle_config(%{image: image}, state) do
    state = %{state | image: image}
    display(state)
    {:noreply, state}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    display(state)
    {:noreply, state}
  end

  def handle_event(_, state) do
    {:noreply, state}
  end

  def handle_info(:display, state) do
    display(state)
    {:noreply, state}
  end

  def display(%{image: image}) do
    case WebP.load(image) do
      nil -> nil
      image -> Octopus.App.update_display(image)
    end
  end
end
