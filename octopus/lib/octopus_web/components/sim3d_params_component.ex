defmodule OctopusWeb.Sim3dParamsComponent do
  use OctopusWeb, :live_component

  alias Octopus.Params.Sim3d

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    config_schema = Sim3d.config_schema()
    config = Sim3d.config()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       config_schema: config_schema,
       config_schema_map: Map.new(config_schema),
       config: config
     )}
  end

  def render(assigns) do
    ~H"""
    <div>
      <form class="space-y-3" phx-change="change" phx-target={@myself}>
        <fieldset :for={{group, entries} <- grouped(@config_schema)} class="space-y-1.5">
          <legend class="text-[0.7rem] font-bold uppercase tracking-wider opacity-50 mb-1">
            {group}
          </legend>
          <div :for={{key, {name, type, opts}} <- entries} class="flex items-center gap-2">
            <%= if type == :boolean do %>
              <label class="text-xs flex-grow cursor-pointer" for={"sim3d-#{key}"}>{name}</label>
              <.config_input key={key} name={name} type={type} opts={opts} value={@config[key]} />
            <% else %>
              <label
                class="text-xs w-24 shrink-0 truncate"
                for={"sim3d-#{key}"}
                title={name}
              >
                {name}
              </label>
              <.config_input
                class="flex-grow"
                key={key}
                name={name}
                type={type}
                opts={opts}
                value={@config[key]}
              />
              <span class="text-xs tabular-nums w-12 text-right opacity-70">{@config[key]}</span>
            <% end %>
          </div>
        </fieldset>
      </form>
    </div>
    """
  end

  # Group schema entries by their `:group` opt, preserving first-seen order of
  # both groups and entries (schema is an ordered keyword list).
  defp grouped(config_schema) do
    Enum.reduce(config_schema, [], fn {_key, {_name, _type, opts}} = entry, acc ->
      group = Map.get(opts, :group, "Sonstige")

      case List.keyfind(acc, group, 0) do
        {^group, items} -> List.keyreplace(acc, group, 0, {group, items ++ [entry]})
        nil -> acc ++ [{group, [entry]}]
      end
    end)
  end

  # Only act on the field the user actually changed (`_target`). Processing the
  # whole form on every change would (a) re-send checkbox booleans on every
  # slider tick and (b) drop unchecked checkboxes (no hidden input), so a slider
  # move could silently flip `render_radar_cones` off. Mirrors AppConfigComponent.
  def handle_event("change", params, socket) do
    schema = socket.assigns.config_schema_map
    changed_keys = target_keys(params)

    parsed =
      params
      |> Map.drop(["_target"])
      |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_unused_") end)
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Enum.map(fn {key, value} -> {key, parse_option(key, value, schema)} end)
      |> Map.new()

    config =
      changed_keys
      |> Enum.flat_map(fn key ->
        cond do
          Map.has_key?(parsed, key) -> [{key, Map.fetch!(parsed, key)}]
          boolean_field?(schema, key) -> [{key, false}]
          true -> []
        end
      end)
      |> Map.new()

    Sim3d.update_config(config)

    {:noreply, assign(socket, config: Map.merge(socket.assigns.config, config))}
  end

  defp target_keys(%{"_target" => target}) when is_list(target) do
    Enum.map(target, &String.to_existing_atom/1)
  end

  defp target_keys(%{"_target" => target}) when is_binary(target) do
    [String.to_existing_atom(target)]
  end

  defp target_keys(params) do
    params
    |> Map.drop(["_target"])
    |> Map.keys()
    |> Enum.map(&String.to_existing_atom/1)
  end

  defp boolean_field?(schema, key) do
    case Map.get(schema, key) do
      {_name, :boolean, _opts} -> true
      _ -> false
    end
  end

  defp parse_option(key, value, config_schema) do
    {_name, type, _opts} = Map.get(config_schema, key)

    case type do
      :float -> value |> Float.parse() |> elem(0)
      :int -> value |> Integer.parse() |> elem(0)
      :boolean -> value == "on"
      :string -> value
    end
  end

  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :name, :string, required: true
  attr :opts, :map, required: true
  attr :debounce, :integer, default: 100
  attr :value, :any, required: true
  attr :disabled, :boolean, default: false
  attr :rest, :global

  defp config_input(%{type: :float} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"sim3d-#{@key}"}
      step={@opts |> Map.get(:step, 0.01)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      disabled={@disabled}
      class="range range-primary range-sm"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :int} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"sim3d-#{@key}"}
      step={@opts |> Map.get(:step, 1)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      disabled={@disabled}
      class="range range-primary range-sm"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :string} = assigns) do
    ~H"""
    <input
      type="text"
      name={@key}
      id={"sim3d-#{@key}"}
      phx-debounce={@debounce}
      value={@value}
      disabled={@disabled}
      class="input input-bordered w-full"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :boolean} = assigns) do
    ~H"""
    <input
      type="checkbox"
      name={@key}
      id={"sim3d-#{@key}"}
      phx-debounce={@debounce}
      checked={@value}
      disabled={@disabled}
      class="checkbox checkbox-primary checkbox-sm shrink-0"
      {@rest}
    />
    """
  end
end
