defmodule OctopusWeb.WoodConfigComponent do
  @moduledoc false
  use OctopusWeb, :live_component

  alias Octopus.AppSupervisor
  alias Octopus.Apps.Wood
  alias Octopus.InstallationTransport

  def mount(socket) do
    {:ok, assign(socket, config_info: nil)}
  end

  def update(%{app_module: Wood} = assigns, socket) do
    config = Map.get(assigns, :config, AppSupervisor.config(assigns.app_id))
    schema_map = Wood.config_schema() |> Map.new()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(config: config, config_schema_map: schema_map, config_info: Wood.config_info(config))}
  end

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def render(assigns) do
    ~H"""
    <div>
      <form class="space-y-4" phx-change="change" phx-target={@myself}>
        <.field app_id={@app_id} key={:mode} config={@config} schema_map={@config_schema_map} />

        <%= if @config.mode == :fullcolor do %>
          <.field app_id={@app_id} key={:color_channel} config={@config} schema_map={@config_schema_map} />

          <div :if={@config.color_channel == :rgb} class="space-y-4">
            <.color_field app_id={@app_id} config={@config} schema_map={@config_schema_map} />
            <.field app_id={@app_id} key={:rgb_mode} config={@config} schema_map={@config_schema_map} />
            <.field
              :if={@config.rgb_mode == :cycle}
              app_id={@app_id}
              key={:hue_cycle_speed}
              config={@config}
              schema_map={@config_schema_map}
            />
          </div>
        <% else %>
          <div :if={@config.mode in [:endless_up, :endless_down, :up_and_down]} class="space-y-4 pl-1 border-l-2 border-base-300 ml-1">
            <.field app_id={@app_id} key={:blob_count} config={@config} schema_map={@config_schema_map} />
            <.field app_id={@app_id} key={:blob_spacing} config={@config} schema_map={@config_schema_map} />
            <.field
              :if={@config.mode == :up_and_down}
              app_id={@app_id}
              key={:bounce}
              config={@config}
              schema_map={@config_schema_map}
            />
          </div>

          <.field app_id={@app_id} key={:blob_size} config={@config} schema_map={@config_schema_map} />
          <.field app_id={@app_id} key={:speed} config={@config} schema_map={@config_schema_map} />
          <.field app_id={@app_id} key={:trail_length} config={@config} schema_map={@config_schema_map} />
          <.field app_id={@app_id} key={:position} config={@config} schema_map={@config_schema_map} />

          <.field app_id={@app_id} key={:color_channel} config={@config} schema_map={@config_schema_map} />

          <div :if={@config.color_channel == :rgb} class="space-y-4">
            <.color_field app_id={@app_id} config={@config} schema_map={@config_schema_map} />
            <.field app_id={@app_id} key={:rgb_mode} config={@config} schema_map={@config_schema_map} />
            <.field
              :if={@config.rgb_mode == :cycle}
              app_id={@app_id}
              key={:hue_cycle_speed}
              config={@config}
              schema_map={@config_schema_map}
            />
          </div>
        <% end %>
      </form>

      <p :if={@config_info} class="text-xs leading-snug opacity-70 mt-3 whitespace-pre-line">
        {@config_info}
      </p>
    </div>
    """
  end

  def handle_event("change", params, socket) do
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
          Map.has_key?(parsed, key) -> [{key, Map.fetch!(parsed, key)}]
          boolean_field?(socket.assigns.config_schema_map, key) -> [{key, false}]
          true -> []
        end
      end)
      |> Map.new()

    new_config = Map.merge(socket.assigns.config, config)

    if route_tweakables_to_transport?(socket, changed_keys) do
      InstallationTransport.set_tweakables(Map.take(new_config, changed_keys))

      {:noreply,
       assign(socket,
         config: AppSupervisor.config(socket.assigns.app_id),
         config_info: Wood.config_info(AppSupervisor.config(socket.assigns.app_id))
       )}
    else
      AppSupervisor.update_config(socket.assigns.app_id, new_config)

      {:noreply,
       assign(socket, config: new_config, config_info: Wood.config_info(new_config))}
    end
  end

  defp route_tweakables_to_transport?(socket, keys) do
    tweakable_keys =
      case InstallationTransport.get_state().now_playing do
        %{app_id: app_id, mode_id: mode_id} when app_id == socket.assigns.app_id ->
          Wood
          |> apply(:mode_tweakables, [mode_id])
          |> Enum.map(& &1.key)
          |> MapSet.new()

        _ ->
          MapSet.new()
      end

    keys != [] and Enum.all?(keys, &MapSet.member?(tweakable_keys, &1))
  end

  attr :app_id, :string, required: true
  attr :key, :atom, required: true
  attr :config, :map, required: true
  attr :schema_map, :map, required: true

  defp field(assigns) do
    {name, type, opts} = Map.fetch!(assigns.schema_map, assigns.key)
    value = Map.get(assigns.config, assigns.key)

    assigns = assign(assigns, name: name, type: type, opts: opts, value: value)

    ~H"""
    <div class="form-control">
      <label :if={@type != :button} class="label" for={"#{@app_id}-#{@key}"}>
        <span class="label-text font-semibold">{@name}</span>
      </label>
      <%= if @type in [:float, :int] do %>
        <div class="flex items-center gap-2">
          <.range_input app_id={@app_id} key={@key} type={@type} opts={@opts} value={@value} />
          <.number_input app_id={@app_id} key={@key} type={@type} opts={@opts} value={@value} />
        </div>
      <% else %>
        <.basic_input app_id={@app_id} key={@key} type={@type} opts={@opts} value={@value} />
      <% end %>
    </div>
    """
  end

  attr :app_id, :string, required: true
  attr :config, :map, required: true
  attr :schema_map, :map, required: true

  defp color_field(assigns) do
    {name, _type, _opts} = Map.fetch!(assigns.schema_map, :color)
    assigns = assign(assigns, name: name, value: assigns.config.color)

    ~H"""
    <div class="form-control">
      <label class="label" for={"#{@app_id}-color"}>
        <span class="label-text font-semibold">{@name}</span>
      </label>
      <div class="flex items-center gap-3">
        <input
          type="color"
          name="color"
          id={"#{@app_id}-color"}
          phx-debounce="100"
          value={@value}
          class="h-12 w-16 cursor-pointer rounded border border-base-300 bg-transparent p-1"
        />
        <input
          type="text"
          value={@value}
          readonly
          class="input input-bordered input-sm w-28 font-mono"
          tabindex="-1"
        />
      </div>
    </div>
    """
  end

  attr :app_id, :string, required: true
  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :opts, :map, required: true
  attr :value, :any, required: true

  defp range_input(assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step={Map.get(@opts, :step, if(@type == :int, do: 1, else: 0.01))}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce="100"
      value={@value}
      oninput={"if(this.nextElementSibling)this.nextElementSibling.value=this.value"}
      class="range range-primary range-sm flex-grow"
    />
    """
  end

  attr :app_id, :string, required: true
  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :opts, :map, required: true
  attr :value, :any, required: true

  defp number_input(assigns) do
    ~H"""
    <input
      type="number"
      name={@key}
      id={"#{@app_id}-#{@key}-number"}
      step={Map.get(@opts, :step, if(@type == :int, do: 1, else: 0.01))}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce="100"
      value={@value}
      oninput={"if(this.previousElementSibling)this.previousElementSibling.value=this.value"}
      class="input input-bordered input-xs w-20 text-right tabular-nums shrink-0"
    />
    """
  end

  attr :app_id, :string, required: true
  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :opts, :map, required: true
  attr :value, :any, required: true

  defp basic_input(assigns) do
    ~H"""
    <%= cond do %>
      <% @type == :boolean -> %>
        <input
          type="checkbox"
          name={@key}
          id={"#{@app_id}-#{@key}"}
          phx-debounce="100"
          checked={@value}
          class="checkbox checkbox-primary"
        />
      <% @type == :select -> %>
        <select
          name={@key}
          id={"#{@app_id}-#{@key}"}
          phx-debounce="100"
          class="select select-bordered w-full"
        >
          <option
            :for={{{label, value}, i} <- Enum.with_index(@opts.options)}
            value={i}
            selected={value == @value}
          >
            {label}
          </option>
        </select>
      <% true -> %>
        <input
          type="text"
          name={@key}
          id={"#{@app_id}-#{@key}"}
          phx-debounce="100"
          value={@value}
          class="input input-bordered w-full"
        />
    <% end %>
    """
  end

  defp target_keys(%{"_target" => target}) when is_list(target), do: Enum.flat_map(target, &schema_key/1)
  defp target_keys(%{"_target" => target}) when is_binary(target), do: schema_key(target)

  defp target_keys(params) do
    params |> Map.drop(["_target"]) |> Map.keys() |> Enum.flat_map(&schema_key/1)
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

  defp parse_option(key, value, schema) do
    {_name, type, opts} = Map.get(schema, key)

    case type do
      :float -> value |> Float.parse() |> elem(0)
      :int -> value |> Integer.parse() |> elem(0)
      :boolean -> value == "on" || value == true
      :select ->
        i = value |> Integer.parse() |> elem(0)
        opts.options |> Enum.at(i) |> elem(1)
      :color -> value
      :string -> value
    end
  end
end
