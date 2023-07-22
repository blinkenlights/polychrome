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
    <form class="flex flex-col gap-4" phx-change="change" phx-target={@myself}>
      <div :for={{key, {name, type, opts}} <- @config_schema}>
        <label class="font-semibold" for={"#{@app_id}-#{key}"} class="block"><%= name %></label>
        <div class="flex flex-row">
          <.config_input
            class="w-full"
            app_id={@app_id}
            key={key}
            name={name}
            type={type}
            opts={opts}
            value={@config[key]}
          />
        </div>
      </div>
    </form>
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

    boolean_off_values =
      socket.assigns.config_schema
      |> Enum.filter(fn {_key, {_name, type, _opts}} -> type == :boolean end)
      |> Enum.map(fn {key, {_name, _type, _opts}} -> {key, false} end)
      |> Map.new()

    config = Map.merge(boolean_off_values, config)

    AppSupervisor.update_config(socket.assigns.app_id, config)

    {:noreply, socket}
  end

  defp parse_option(key, value, config_schema) do
    type = config_schema |> Map.get(key) |> elem(1)

    case type do
      :float ->
        value |> Float.parse() |> elem(0)

      :int ->
        value |> Integer.parse() |> elem(0)

      :boolean ->
        value == "on"

      :select ->
        {_name, _type, %{options: options}} = Map.get(config_schema, key)
        i = value |> Integer.parse() |> elem(0)
        {_name, value} = Enum.at(options, i)
        value

      :string ->
        value
    end
  end

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:name, :string, required: true)
  attr(:opts, :map, required: true)
  attr(:debounce, :integer, default: 0)
  attr(:value, :any, required: true)
  attr(:rest, :global)

  defp config_input(%{type: :float} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step={@opts |> Map.get(:step, 0.01)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      {@rest}
    />
    """
  end

  defp config_input(%{type: :int} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step={@opts |> Map.get(:step, 1)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      {@rest}
    />
    """
  end

  defp config_input(%{type: :string} = assigns) do
    ~H"""
    <input
      type="text"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      phx-debounce={@debounce}
      value={@value}
      {@rest}
    />
    """
  end

  defp config_input(%{type: :boolean} = assigns) do
    ~H"""
    <div {@rest}>
      <input
        type="checkbox"
        name={@key}
        id={"#{@app_id}-#{@key}"}
        phx-debounce={@debounce}
        checked={@value}
      />
    </div>
    """
  end

  defp config_input(%{type: :select} = assigns) do
    ~H"""
    <select name={@key} id={"#{@app_id}-#{@key}"} phx-debounce={@debounce} {@rest}>
      <option :for={{{name, _value}, i} <- Enum.with_index(@opts.options)} value={i}>
        <%= name %>
      </option>
    </select>
    """
  end
end
