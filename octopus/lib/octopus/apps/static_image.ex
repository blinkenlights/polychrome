defmodule Octopus.Apps.StaticImage do
  alias Octopus.Protobuf.ControlEvent
  alias Octopus.WebP
  alias Octopus.Canvas
  use Octopus.App, category: :animation

  def name, do: "Static Image"

  def config_schema do
    %{
      image: {"Static Image", :string, %{default: "polychrome_eventphone"}}
    }
  end

  def get_config(%{image: image}) do
    %{image: image}
  end

  def init(%{image: image}) do
    send(self(), :display)
    {:ok, %{image: image}}
  end

  def handle_config(%{image: image}, state) do
    state = %{state | image: image}
    display(state)
    {:noreply, state}
  end

  def handle_control_event(%ControlEvent{type: type}, state)
      when type in [:APP_SELECTED, :APP_STARTED] do
    display(state)
    {:noreply, state}
  end

  def handle_control_event(_, state) do
    {:noreply, state}
  end

  def handle_info(:display, state) do
    display(state)
    {:noreply, state}
  end

  def display(%{image: image}) do
    case WebP.load(image) do
      nil -> nil
      image -> image |> Canvas.to_frame(drop: image.width > 80) |> send_frame()
    end
  end
end
