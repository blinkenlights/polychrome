defmodule OctopusWeb.AppConfigComponent do
  use OctopusWeb, :live_component

  alias Octopus.{App, AppSupervisor}
  alias Octopus.InstallationTransport

  def mount(socket) do
    {:ok, assign(socket, config_info: nil)}
  end

  def update(%{app_module: module} = assigns, socket) do
    config_schema = App.config_schema(module)
    config = Map.get(assigns, :config, AppSupervisor.config(assigns.app_id))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       config_schema: config_schema,
       config_schema_map: Map.new(config_schema),
       config: config,
       config_info: config_info(module, config)
     )}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <form class="space-y-4" phx-change="change" phx-target={@myself}>
        <div :for={{key, {name, type, opts}} <- visible_entries(@config_schema, @config)} class="form-control">
          <label :if={type != :button} class="label" for={"#{@app_id}-#{key}"}>
            <span class="label-text font-semibold">{name}</span>
          </label>
          <%= cond do %>
            <% type in [:float, :int] -> %>
              <div class="flex items-center gap-2">
                <.config_input
                  class="flex-grow"
                  app_id={@app_id}
                  key={key}
                  name={name}
                  type={type}
                  opts={opts}
                  value={@config[key]}
                  target={@myself}
                />
                <.config_number
                  app_id={@app_id}
                  key={key}
                  type={type}
                  opts={opts}
                  value={@config[key]}
                />
              </div>
            <% true -> %>
              <.config_input
                class="w-full"
                app_id={@app_id}
                key={key}
                name={name}
                type={type}
                opts={opts}
                value={@config[key]}
                target={@myself}
              />
          <% end %>
        </div>
      </form>
      <p
        :if={@config_info}
        class="text-xs leading-snug opacity-70 mt-3 whitespace-pre-line"
      >
        {@config_info}
      </p>
    </div>
    """
  end

  def handle_event("config_action", %{"key" => key}, socket) do
    key = String.to_existing_atom(key)
    module = socket.assigns.app_module

    if function_exported?(module, :handle_config_action, 1) do
      module.handle_config_action(key)
    end

    {:noreply, socket}
  end

  def handle_event("change", params, socket) do
    handle_config_change(params, socket)
  end

  defp handle_config_change(params, socket) do
    changed_keys = target_keys(params)

    parsed =
      params
      |> Map.drop(["_target"])
      |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_unused_") end)
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Enum.map(fn {key, value} ->
        {key, parse_option(key, value, socket.assigns.config_schema_map)}
      end)
      |> Map.new()

    config =
      changed_keys
      |> Enum.flat_map(fn key ->
        cond do
          Map.has_key?(parsed, key) ->
            [{key, Map.fetch!(parsed, key)}]

          boolean_field?(socket.assigns.config_schema_map, key) ->
            [{key, false}]

          true ->
            []
        end
      end)
      |> Map.new()

    new_config = Map.merge(socket.assigns.config, config)

    if route_tweakables_to_transport?(socket, changed_keys) do
      InstallationTransport.set_tweakables(Map.take(new_config, changed_keys))

      refreshed = AppSupervisor.config(socket.assigns.app_id)

      {:noreply,
       assign(socket,
         config: refreshed,
         config_info: config_info(socket.assigns.app_module, refreshed)
       )}
    else
      AppSupervisor.update_config(socket.assigns.app_id, new_config)

      {:noreply,
       assign(socket,
         config: new_config,
         config_info: config_info(socket.assigns.app_module, new_config)
       )}
    end
  end

  defp route_tweakables_to_transport?(socket, keys) do
    tweakable_keys =
      case InstallationTransport.get_state().now_playing do
        %{app_id: app_id, mode_id: mode_id} when app_id == socket.assigns.app_id ->
          socket.assigns.app_module
          |> apply(:mode_tweakables, [mode_id])
          |> Enum.map(& &1.key)
          |> MapSet.new()

        _ ->
          MapSet.new()
      end

    keys != [] and Enum.all?(keys, &MapSet.member?(tweakable_keys, &1))
  end

  defp target_keys(%{"_target" => target}) when is_list(target) do
    target |> Enum.flat_map(&schema_key/1)
  end

  defp target_keys(%{"_target" => target}) when is_binary(target) do
    schema_key(target)
  end

  defp target_keys(params) do
    params
    |> Map.drop(["_target"])
    |> Map.keys()
    |> Enum.flat_map(&schema_key/1)
  end

  defp schema_key(key) do
    [String.to_existing_atom(key)]
  rescue
    ArgumentError -> []
  end

  defp boolean_field?(schema, key) do
    case Map.get(schema, key) do
      {_name, :boolean, _opts} -> true
      _ -> false
    end
  end

  defp config_info(module, config) do
    if function_exported?(module, :config_info, 1) do
      module.config_info(config)
    end
  end

  defp visible_entries(config_schema, config) do
    Enum.filter(config_schema, fn {_key, {_name, type, opts}} ->
      type != :internal &&
        case Map.get(opts, :visible_when) do
          nil -> true
          {dep_key, allowed} -> Map.get(config, dep_key) in allowed
        end
    end)
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

      type when type in [:string, :color] ->
        value
    end
  end

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:name, :string, required: true)
  attr(:opts, :map, required: true)
  attr(:debounce, :integer, default: 100)
  attr(:value, :any, required: true)
  attr(:target, :any, default: nil)
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
      oninput={"if(this.nextElementSibling)this.nextElementSibling.value=this.value"}
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
      id={"#{@app_id}-#{@key}"}
      step={@opts |> Map.get(:step, 1)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      oninput={"if(this.nextElementSibling)this.nextElementSibling.value=this.value"}
      class="range range-primary range-sm"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :color} = assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <input
        type="color"
        name={@key}
        id={"#{@app_id}-#{@key}"}
        phx-debounce={@debounce}
        value={@value}
        class="h-12 w-16 cursor-pointer rounded border border-base-300 bg-transparent p-1"
        {@rest}
      />
      <input
        type="text"
        value={@value}
        readonly
        class="input input-bordered input-sm w-28 font-mono"
        tabindex="-1"
      />
    </div>
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
      id={"#{@app_id}-#{@key}"}
      phx-debounce={@debounce}
      checked={@value}
      class="checkbox checkbox-primary"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :select} = assigns) do
    index =
      assigns.opts.options
      |> Enum.find_index(fn {_name, val} -> val == assigns.value end)
      |> case do
        nil -> 0
        i -> i
      end

    assigns = assign(assigns, :selected_index, index)

    ~H"""
    <select
      name={@key}
      id={"#{@app_id}-#{@key}"}
      phx-debounce={@debounce}
      class="select select-bordered w-full"
      value={@selected_index}
      {@rest}
    >
      <option
        :for={{{name, _value}, i} <- Enum.with_index(@opts.options)}
        value={i}
        selected={i == @selected_index}
      >
        {name}
      </option>
    </select>
    """
  end

  defp config_input(%{type: :button} = assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@app_id}-#{@key}"}
      phx-click="config_action"
      phx-value-key={@key}
      phx-target={@target}
      class="btn btn-primary btn-sm w-full"
      {@rest}
    >
      {@name}
    </button>
    """
  end

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:opts, :map, required: true)
  attr(:debounce, :integer, default: 100)
  attr(:value, :any, required: true)
  attr(:rest, :global)

  defp config_number(assigns) do
    ~H"""
    <input
      type="number"
      name={@key}
      id={"#{@app_id}-#{@key}-number"}
      step={@opts |> Map.get(:step, if(@type == :int, do: 1, else: 0.01))}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      oninput={"if(this.previousElementSibling)this.previousElementSibling.value=this.value"}
      class="input input-bordered input-xs w-20 text-right tabular-nums shrink-0"
      {@rest}
    />
    """
  end
end
