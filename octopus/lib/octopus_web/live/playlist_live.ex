defmodule OctopusWeb.PlaylistLive do
  use OctopusWeb, :live_view

  alias Phoenix.LiveView.Socket
  alias Ecto.Changeset
  alias Octopus.PlaylistScheduler
  alias Octopus.PlaylistScheduler.Playlist

  def mount(%{"id" => id}, _session, socket) do
    playlist = %Playlist{} = PlaylistScheduler.get_playlist(id)

    socket =
      socket
      |> assign(playlist_id: id)
      |> assign(playlist: playlist)
      |> assign(name: playlist.name)
      |> assign(animations: Jason.encode!(playlist.animations))
      |> put_flash(:error, nil)
      |> assign(info: nil)
      |> validate_animations()
      |> format_animations()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto w-full flex flex-row py-2">
      <form phx-change="name-update" class="w-full">
        <input class="text-2xl font-semibold leading-loose w-full border-none" type="text" name="name" value={@name} />
      </form>
      <button class="border mx-2 py-1 px-2 rounded bg-slate-300" phx-click="save">Save</button>
    </div>
    <LiveMonacoEditor.code_editor
      value={@animations}
      class="h-full w-full"
      opts={
        Map.merge(
          LiveMonacoEditor.default_opts(),
          %{"language" => "json"}
        )
      }
    />
    """
  end

  def handle_event("editor-update", %{"content" => content}, socket) do
    socket =
      socket
      |> assign(animations: content)
      |> validate_animations()
      |> format_animations()
      |> clear_flash(:info)

    {:noreply, socket}
  end

  def handle_event("name-update", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name)}
  end

  def handle_event("save", _params, socket) do
    socket =
      socket
      |> validate_animations()
      |> store_animations()

    {:noreply, socket}
  end

  def validate_animations(socket) do
    case Jason.decode(socket.assigns.animations) do
      {:error, _error} ->
        socket
        |> assign(valid?: false)
        |> put_flash(:error, "Invalid JSON")

      {:ok, list} ->
        Playlist.changeset(socket.assigns.playlist, %{
          animations: list
        })
        |> case do
          %Changeset{valid?: true} ->
            socket
            |> assign(valid?: true)
            |> clear_flash(:error)

          %Changeset{valid?: false} = changeset ->
            socket
            |> assign(valid?: false)
            |> put_flash(:error, render_animation_errors(changeset))
        end
    end
  end

  def format_animations(%Socket{assigns: %{valid?: true}} = socket) do
    list = Jason.decode!(socket.assigns.animations)

    json_str =
      list
      |> Enum.map(fn map -> "  #{Jason.encode!(map)}" end)
      |> Enum.join(",\n")

    socket
    |> assign(animations: "[\n#{json_str}\n]")
  end

  def format_animations(socket), do: socket

  def store_animations(%Socket{assigns: %{valid?: true}} = socket) do
    list = Jason.decode!(socket.assigns.animations)

    PlaylistScheduler.update_playlist!(socket.assigns.playlist_id, %{
      animations: list,
      name: socket.assigns.name
    })

    socket
    |> put_flash(:info, "Playlist Saved.")
  end

  def store_animations(socket) do
    socket
    |> put_flash(:error, "Not saved. Playlist is invalid.")
  end

  def render_animation_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {message, values} ->
      Enum.reduce(values, message, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Map.get(:animations)
    |> Enum.filter(&(&1 != %{}))
    |> Enum.with_index()
    |> Enum.map(fn {errors, index} ->
      msg =
        errors
        |> Enum.map(fn {k, v} -> "#{k} #{v}" end)
        |> Enum.join(", ")

      "Line #{index + 2}: #{msg}"
    end)
  end
end
