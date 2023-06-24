defmodule OctopusWeb.AppConfigComponent do
  use OctopusWeb, :live_component

  alias Octopus.AppSupervisor

  def mount(socket) do
    {:ok, socket}
  end

  def update(%{app_module: module} = assigns, socket) do
    config_schema = apply(module, :config_schema, [])
    config = AppSupervisor.config(assigns.app_id)
    {:ok, socket |> assign(assigns) |> assign(config_schema: config_schema, config: config)}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <div :for={{key, {name, type, opts}} <- @config_schema}>
        <span><%= name %></span>
        <form phx-change="change" phx-target={@myself}>
          <.config_input
            app_id={@app_id}
            key={key}
            name={name}
            type={type}
            opts={opts}
            value={@config[key]}
          />
        </form>
      </div>
    </div>
    """
  end

  def handle_event("change", params, socket) do
    config =
      params
      |> Map.drop(["_target"])
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Enum.map(fn {key, value} ->
        {key, parse_option(key, value, socket.assigns.config_schema)}
      end)
      |> Map.new()

    AppSupervisor.update_config(socket.assigns.app_id, config)

    {:noreply, socket}
  end

  defp parse_option(key, value, config_schema) do
    type = config_schema |> Map.get(key) |> elem(1)

    case type do
      :float -> value |> Float.parse() |> elem(0)
      :int -> value |> Integer.parse() |> elem(0)
      :string -> value
    end
  end

  attr :app_id, :string, required: true
  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :name, :string, required: true
  attr :opts, :map, required: true
  attr :debounce, :integer, default: 0
  attr :value, :any, required: true

  defp config_input(%{type: :float} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step="0.01"
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
    />
    """
  end

  defp config_input(%{type: :int} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step="1"
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
    />
    """
  end

  defp config_input(%{type: :string} = assigns) do
    ~H"""
    <input type="text" name={@key} id={"#{@app_id}-#{@key}"} phx-debounce={@debounce} value={@value} />
    """
  end
end
