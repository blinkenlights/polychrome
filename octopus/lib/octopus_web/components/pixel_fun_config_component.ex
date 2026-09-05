defmodule OctopusWeb.PixelFunConfigComponent do
  use OctopusWeb, :live_component

  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun
  alias Octopus.Apps.PixelFun.ScenePresets
  alias Octopus.InstallationTransport

  @known_idents ~w(
    x y nx ny nz t i l m h pi PI tau Tau
    rand random abs sqrt exp log hypot sin cos tan asin acos atan atan2
    asinh acosh atanh sinh cosh tanh floor ceil round fract noise
  )

  def mount(socket) do
    {:ok,
     assign(socket,
       presets: [],
       selected_preset_id: nil,
       config_info: nil,
       config: %{},
       queue_position: nil
     )}
  end

  def update(%{app_module: PixelFun} = assigns, socket) do
    config =
      cond do
        is_map(assigns[:config]) -> assigns.config
        is_map(socket.assigns[:config]) and map_size(socket.assigns.config) > 0 -> socket.assigns.config
        true -> AppSupervisor.config(assigns.app_id)
      end

    live_id = config[:live_scene_id] || ScenePresets.id_for_config(config)
    queue_pos = queue_position_for(live_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       config: config,
       config_schema: PixelFun.config_schema(),
       presets: ScenePresets.list_all(),
       config_info: PixelFun.config_info(config),
       selected_preset_id: live_id,
       queue_position: queue_pos
     )
     |> assign_editor_view()}
  end

  def update(assigns, socket), do: {:ok, assign(socket, assigns) |> assign_editor_view()}

  def render(assigns) do
    ~H"""
    <div class="pf-root rounded-xl space-y-4">
      <style>
        .pf-root{font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif}
        .pf-mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,monospace}
      </style>

      <div class="flex flex-wrap items-center gap-3">
        <h2 class="text-lg font-semibold flex-1">{@editor_name}</h2>
        <.live_badge :if={@live_preset} />
        <span :if={@queue_position} class="badge badge-outline badge-sm">Nr. {@queue_position}</span>
        <span
          :if={@dirty}
          class="badge gap-1 border-warning text-warning bg-transparent"
        >
          <span class="w-2 h-2 rounded-full bg-warning" /> Unsaved edits
        </span>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4 gap-3">
          <label class="text-sm font-semibold" for={"#{@app_id}-scene-picker"}>Edit scene</label>
          <select
            id={"#{@app_id}-scene-picker"}
            class="select select-bordered w-full"
            phx-change="select_scene"
            phx-target={@myself}
            name="preset_id"
          >
            <option value="new">＋ New scene (from wall)</option>
            <option
              :for={preset <- @presets}
              value={preset.id}
              selected={preset.id == @selected_preset_id}
            >
              {preset.name}
            </option>
          </select>
        </div>
      </div>

      <.scene_editor {assigns} />

    </div>
    """
  end

  defp scene_editor(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-4">
        <form phx-change="change" phx-target={@myself} class="space-y-4" id={"#{@app_id}-editor"}>
          <div>
            <label class="label" for={"#{@app_id}-program"}>
              <span class="label-text font-semibold">Formula</span>
            </label>
            <div class="pf-mono text-[11px] opacity-60 mb-1">x y nx ny nz · t i · l m h (audio) · pi tau</div>
            <input
              type="text"
              name="program"
              id={"#{@app_id}-program"}
              phx-debounce="150"
              value={@config[:program]}
              class={[
                "input input-bordered w-full pf-mono text-sm",
                !@formula_valid && "border-error focus:border-error"
              ]}
            />
            <p :if={@formula_valid} class="text-xs mt-1 text-success">
              ✓ Valid — updating the wall as you type
            </p>
            <p :if={!@formula_valid} class="text-xs mt-1 text-error">
              ✕ Can't read this — '{@formula_error}' isn't a function. The wall keeps the last valid formula.
            </p>
          </div>

          <div :for={{key, {name, type, opts}} <- scene_entries(@config_schema, @config)}>
            <div class="flex items-center justify-between">
              <label class="label-text font-semibold" for={"#{@app_id}-#{key}"}>{name}</label>
              <span :if={type != :select} class="pf-mono text-sm opacity-80">{format_slider(@config[key])}</span>
            </div>
            <.scene_input app_id={@app_id} key={key} type={type} opts={opts} value={@config[key]} />
          </div>
        </form>

        <div class="flex flex-wrap gap-2 items-center">
          <button
            type="button"
            class={[
              "btn btn-sm",
              @config[:time_frozen] && "btn-warning",
              !@config[:time_frozen] && "btn-outline"
            ]}
            phx-click="toggle_time_frozen"
            phx-target={@myself}
            id={"#{@app_id}-toggle-time-frozen"}
          >
            {if @config[:time_frozen], do: "▶ Resume time", else: "⏸ Freeze time"}
          </button>
        </div>

        <div class="flex flex-wrap gap-2 items-center">
          <button :if={@dirty} class="btn btn-ghost" phx-click="discard_changes" phx-target={@myself}>
            Discard edits
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp live_badge(assigns) do
    ~H"""
    <span class="badge badge-sm badge-success font-semibold">LIVE</span>
    """
  end

  attr :app_id, :string, required: true
  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :opts, :map, required: true
  attr :value, :any, required: true

  defp slider_input(assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step={@opts |> Map.get(:step, if(@type == :int, do: 1, else: 0.01))}
      min={@opts[:min]}
      max={@opts[:max]}
      value={@value}
      class="range range-primary range-sm w-full"
    />
    """
  end

  defp select_input(assigns) do
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
      phx-debounce="50"
      class="select select-bordered w-full"
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

  defp scene_input(%{type: :select} = assigns), do: select_input(assigns)
  defp scene_input(assigns), do: slider_input(assigns)

  def handle_event("select_scene", %{"preset_id" => "new"}, socket) do
    {:noreply, assign(socket, selected_preset_id: "new") |> assign_editor_view()}
  end

  def handle_event("select_scene", %{"preset_id" => id}, socket) do
    case ScenePresets.get(id) do
      nil ->
        {:noreply, socket}

      _preset ->
        PixelFun.apply_mode(socket.assigns.app_id, id)

        {:noreply,
         socket
         |> assign(config: AppSupervisor.config(socket.assigns.app_id), selected_preset_id: id)
         |> assign_editor_view()}
    end
  end

  def handle_event("toggle_time_frozen", _params, socket) do
    AppSupervisor.update_config(socket.assigns.app_id, %{
      time_frozen: !(socket.assigns.config[:time_frozen] || false)
    })

    {:noreply,
     socket
     |> assign(config: AppSupervisor.config(socket.assigns.app_id))
     |> assign_editor_view()}
  end

  def handle_event("change", params, socket) do
    keys = target_keys(params)

    config =
      Enum.reduce(keys, socket.assigns.config, fn key, acc ->
        case Map.fetch(params, Atom.to_string(key)) do
          {:ok, value} -> Map.put(acc, key, parse_option(key, value, socket.assigns.config_schema))
          :error -> acc
        end
      end)

    if route_tweakables_to_transport?(socket, keys) do
      InstallationTransport.set_tweakables(Map.take(config, keys))

      {:noreply,
       socket
       |> assign(config: AppSupervisor.config(socket.assigns.app_id))
       |> assign_editor_view()}
    else
      AppSupervisor.update_config(socket.assigns.app_id, config)

      {:noreply,
       socket
       |> assign(config: AppSupervisor.config(socket.assigns.app_id))
       |> assign_editor_view()}
    end
  end

  def handle_event("discard_changes", _params, socket) do
    preset = socket.assigns.editor_preset

    config =
      if preset do
        ScenePresets.to_config(preset)
      else
        socket.assigns.config
      end

    AppSupervisor.update_config(socket.assigns.app_id, config)

    {:noreply,
     socket
     |> assign(config: AppSupervisor.config(socket.assigns.app_id))
     |> assign_editor_view()}
  end

  defp assign_editor_view(socket) do
    config = socket.assigns.config
    presets = socket.assigns.presets
    by_id = Map.new(presets, &{&1.id, &1})

    live_id = config[:live_scene_id] || ScenePresets.id_for_config(config)
    live_preset = by_id[live_id]

    editor_preset =
      case socket.assigns.selected_preset_id do
        "new" -> nil
        id when is_binary(id) -> by_id[id]
        _ -> live_preset
      end

    dirty = not is_nil(editor_preset) and not ScenePresets.config_matches?(config, editor_preset)
    formula_valid = ScenePresets.validate_formula(config[:program] || "") == :ok

    assign(socket,
      live_preset: live_preset,
      editor_preset: editor_preset,
      editor_name: (editor_preset && editor_preset.name) || "New scene",
      dirty: dirty,
      formula_valid: formula_valid,
      formula_error: formula_error_token(config[:program] || ""),
      queue_position: queue_position_for(live_id)
    )
  end

  defp queue_position_for(live_id) when is_binary(live_id) do
    transport = InstallationTransport.get_state()

    transport.queue
    |> Enum.find_index(fn entry ->
      entry.app == PixelFun and entry.mode_id == live_id
    end)
    |> case do
      nil -> nil
      index -> index + 1
    end
  end

  defp queue_position_for(_), do: nil

  defp route_tweakables_to_transport?(socket, keys) do
    tweakable_keys =
      case InstallationTransport.get_state().now_playing do
        %{app_id: app_id, mode_id: mode_id} when app_id == socket.assigns.app_id ->
          apply(PixelFun, :mode_tweakables, [mode_id]) |> Enum.map(& &1.key) |> MapSet.new()

        _ ->
          MapSet.new()
      end

    keys != [] and Enum.all?(keys, &MapSet.member?(tweakable_keys, &1))
  end

  defp scene_entries(config_schema, config) do
    config_schema
    |> Enum.reject(fn {key, {_name, type, _opts}} ->
      key == :program or type == :internal
    end)
    |> Enum.filter(fn {_key, {_name, _type, opts}} ->
      case Map.get(opts, :visible_when) do
        nil -> true
        {dep_key, allowed} -> Map.get(config, dep_key) in allowed
      end
    end)
  end

  defp target_keys(%{"_target" => target}) when is_list(target), do: Enum.flat_map(target, &schema_key/1)
  defp target_keys(%{"_target" => target}) when is_binary(target), do: schema_key(target)
  defp target_keys(_), do: []

  defp schema_key(key) do
    [String.to_existing_atom(key)]
  rescue
    ArgumentError -> []
  end

  defp parse_option(key, value, config_schema) do
    type = config_schema |> Map.get(key) |> elem(1)

    case type do
      :float -> value |> Float.parse() |> elem(0)
      :int -> value |> Integer.parse() |> elem(0)
      :select ->
        index = String.to_integer(value)
        {_name, val} = config_schema |> Map.get(key) |> elem(2) |> Map.fetch!(:options) |> Enum.at(index)
        val

      _ -> value
    end
  end

  defp format_slider(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp format_slider(value) when is_integer(value), do: Integer.to_string(value)
  defp format_slider(value), do: to_string(value)

  defp formula_error_token(formula) do
    case ScenePresets.validate_formula(formula) do
      :ok -> nil
      :error ->
        Regex.scan(~r/[A-Za-z_][A-Za-z0-9_]*/, formula)
        |> List.flatten()
        |> Enum.find(&(&1 not in @known_idents))
        |> Kernel.||("?")
    end
  end

end
