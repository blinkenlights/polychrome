defmodule OctopusWeb.PixelFunConfigComponent do
  use OctopusWeb, :live_component

  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun
  alias Octopus.Apps.PixelFun.ScenePresets

  @scene_keys [:program, :color_interval, :translate_scale, :rotate_scale, :zoom_scale]

  def mount(socket) do
    {:ok,
     assign(socket,
       presets: [],
       loaded_preset_id: nil,
       saved_snapshot: nil,
       dirty: false,
       formula_valid: true,
       preset_message: nil,
       show_save_preset_modal: false,
       preset_save_name: "",
       config_info: nil
     )}
  end

  def update(assigns, socket) do
    prev_config = socket.assigns[:config]
    prev_live_id = live_preset_id(prev_config || %{})
    incoming_config = Map.get(assigns, :config)

    socket = assign(socket, assigns)

    case socket.assigns[:app_module] do
      PixelFun ->
        config =
          cond do
            is_map(incoming_config) -> incoming_config
            is_map(prev_config) -> prev_config
            true -> AppSupervisor.config(socket.assigns.app_id)
          end

        live_id = live_preset_id(config)

        external_update? =
          is_map(incoming_config) &&
            (config_changed?(prev_config, incoming_config) || prev_live_id != live_id)

        {:ok,
         socket
         |> assign(
           config_schema: PixelFun.config_schema(),
           config_schema_map: PixelFun.config_schema() |> Map.new(),
           config: config,
           presets: ScenePresets.list_all(),
           live_preset_id: live_id,
           active_preset_id: live_id,
           formula_valid: ScenePresets.validate_formula(config[:program]) == :ok,
           config_info: PixelFun.config_info(config)
         )
         |> maybe_sync_external_config(external_update?)
         |> assign_dirty_state()}

      _ ->
        {:ok, socket}
    end
  end

  def render(assigns) do
    live_id = live_preset_id(assigns.config)
    cycle_ids = MapSet.new(assigns.config[:cycle_preset_ids] || [])

    assigns =
      assigns
      |> assign(:cycle_ids, cycle_ids)
      |> assign(:live_preset_id, live_id)
      |> assign(:active_preset_id, live_id)

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 lg:gap-8">
      <div class="space-y-4 min-w-0">
        <h2 class="text-lg font-semibold">Scene presets</h2>

        <form phx-change="change" phx-target={@myself}>
          <label class="label" for={"#{@app_id}-cycle-interval"}>
            <span class="label-text font-semibold">Cycle interval (minutes)</span>
          </label>
          <div class="flex items-center gap-2">
            <input
              type="range"
              name="cycle_interval_minutes"
              id={"#{@app_id}-cycle-interval"}
              min="1"
              max="120"
              step="1"
              phx-debounce="100"
              value={@config[:cycle_interval_minutes]}
              oninput={"if(this.nextElementSibling)this.nextElementSibling.value=this.value"}
              class="range range-primary range-sm flex-grow"
            />
            <input
              type="number"
              name="cycle_interval_minutes"
              id={"#{@app_id}-cycle-interval-number"}
              min="1"
              max="120"
              step="1"
              phx-debounce="100"
              value={@config[:cycle_interval_minutes]}
              oninput={"if(this.previousElementSibling)this.previousElementSibling.value=this.value"}
              class="input input-bordered input-xs w-20 text-right tabular-nums shrink-0"
            />
          </div>
          <p class="text-xs opacity-70 mt-1">
            Enable loop on two or more tiles to auto-rotate. One tile stays fixed; none means manual only.
          </p>
        </form>

        <div
          id={"#{@app_id}-presets-#{@live_preset_id}"}
          class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-2 xl:grid-cols-3 gap-3"
        >
          <div
            :for={preset <- @presets}
            id={"#{@app_id}-preset-#{preset.id}"}
            phx-click="apply_preset"
            phx-value-id={preset.id}
            phx-target={@myself}
            class={[
              "card border-2 cursor-pointer transition-all hover:shadow-md bg-base-100 min-w-0 relative",
              @live_preset_id == preset.id && "border-primary shadow-md ring-2 ring-primary ring-offset-2 ring-offset-base-100",
              @live_preset_id != preset.id && "border-base-300"
            ]}
          >
            <span
              :if={@live_preset_id == preset.id}
              class="badge badge-primary badge-xs absolute top-2 right-2 z-10"
            >
              Live
            </span>
            <div class="h-2 rounded-t-xl" style={"background-color: #{preset.accent_color}"} />
            <div class="card-body p-3 gap-2">
              <div class="flex items-start justify-between gap-2 pr-10">
                <h3 class="font-semibold text-sm leading-tight">{preset.name}</h3>
                <label class="label cursor-pointer gap-1 py-0 shrink-0" onclick="event.stopPropagation()">
                  <span class="label-text text-xs">Loop</span>
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary checkbox-xs"
                    checked={MapSet.member?(@cycle_ids, preset.id)}
                    phx-click="toggle_cycle"
                    phx-value-id={preset.id}
                    phx-target={@myself}
                  />
                </label>
              </div>
              <p class="text-xs opacity-70 leading-snug break-words">{ScenePresets.summary(preset)}</p>
              <button
                :if={!preset.builtin}
                type="button"
                class="btn btn-ghost btn-xs self-start text-error"
                phx-click="delete_preset"
                phx-value-id={preset.id}
                phx-target={@myself}
                onclick="event.stopPropagation()"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="space-y-4 min-w-0">
        <div>
          <h2 class="text-lg font-semibold">Scene settings</h2>
          <p :if={@live_preset_id != "custom"} class="text-sm opacity-70 mt-1">
            Currently running: <span class="font-medium">{preset_name(@presets, @live_preset_id)}</span>
          </p>
          <p :if={@live_preset_id == "custom"} class="text-sm opacity-70 mt-1">
            Custom scene — not matching any saved preset
          </p>
        </div>

        <div
          :if={@dirty}
          class="alert alert-warning py-2 text-sm flex flex-wrap gap-2 items-center"
        >
          <span class="flex-grow">Scene changed from loaded preset.</span>
          <button
            type="button"
            class="btn btn-warning btn-xs"
            phx-click="overwrite_preset"
            phx-target={@myself}
          >
            Overwrite preset
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="discard_changes"
            phx-target={@myself}
          >
            Discard
          </button>
          <button
            type="button"
            class="btn btn-primary btn-xs"
            phx-click="open_save_preset_modal"
            phx-target={@myself}
          >
            Save as new…
          </button>
        </div>

        <form
          id={"#{@app_id}-scene-#{@live_preset_id}"}
          class="space-y-4"
          phx-change="change"
          phx-target={@myself}
        >
          <div class="form-control">
            <label class="label" for={"#{@app_id}-program"}>
              <span class="label-text font-semibold">Formula</span>
            </label>
            <input
              type="text"
              name="program"
              id={"#{@app_id}-program"}
              phx-debounce="100"
              value={@config[:program]}
              class="input input-bordered w-full font-mono text-sm"
            />
            <p class={["text-xs mt-1", @formula_valid && "text-success", !@formula_valid && "text-error"]}>
              {if @formula_valid, do: "Valid formula", else: "Invalid formula syntax"}
            </p>
          </div>

          <div
            :for={{key, {name, type, opts}} <- scene_entries(@config_schema)}
            class="form-control"
          >
            <label class="label" for={"#{@app_id}-#{key}"}>
              <span class="label-text font-semibold">{name}</span>
            </label>
            <div class="flex items-center gap-2">
              <.slider_input
                app_id={@app_id}
                key={key}
                type={type}
                opts={opts}
                value={@config[key]}
              />
              <.number_input app_id={@app_id} key={key} type={type} opts={opts} value={@config[key]} />
            </div>
          </div>
        </form>

        <p :if={@config_info} class="text-xs leading-snug opacity-70 whitespace-pre-line">
          {@config_info}
        </p>

        <p
          :if={@preset_message}
          class={[
            "text-xs",
            match?({:ok, _}, @preset_message) && "text-success",
            match?({:error, _}, @preset_message) && "text-error"
          ]}
        >
          {preset_message_text(@preset_message)}
        </p>
      </div>

      <div :if={@show_save_preset_modal} class="modal modal-open" role="dialog" aria-modal="true">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Save scene preset</h3>
          <p class="py-2 text-sm opacity-70">
            Save the current formula and slider values under a new name.
          </p>
          <form
            id={"#{@app_id}-save-preset-form"}
            phx-submit="save_preset"
            phx-target={@myself}
            class="space-y-4"
          >
            <input
              type="text"
              name="preset_save_name"
              id={"#{@app_id}-preset-save-name"}
              phx-debounce="100"
              phx-change="change"
              phx-target={@myself}
              value={@preset_save_name}
              placeholder="Preset name"
              autofocus
              class="input input-bordered w-full"
            />
            <div class="modal-action mt-0">
              <button
                type="button"
                phx-click="close_save_preset_modal"
                phx-target={@myself}
                class="btn btn-ghost"
              >
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" disabled={!@formula_valid}>
                Save
              </button>
            </div>
          </form>
        </div>
        <button
          type="button"
          class="modal-backdrop"
          phx-click="close_save_preset_modal"
          phx-target={@myself}
          aria-label="Close"
        />
      </div>
    </div>
    """
  end

  def handle_event("apply_preset", %{"id" => preset_id}, socket) do
    case ScenePresets.get(preset_id) do
      nil ->
        {:noreply, socket}

      preset ->
        snapshot = scene_snapshot(preset)
        new_config = merge_scene_config(socket.assigns.config, ScenePresets.to_config(preset))

        :ok = AppSupervisor.update_config(socket.assigns.app_id, new_config)

        {:noreply, sync_from_app_config(socket, external: false, preset_id: preset_id, snapshot: snapshot)}
    end
  end

  def handle_event("toggle_cycle", %{"id" => preset_id}, socket) do
    ids = socket.assigns.config[:cycle_preset_ids] || []

    new_ids =
      if preset_id in ids do
        List.delete(ids, preset_id)
      else
        ids ++ [preset_id]
      end

    push_cycle_config(socket, new_ids)
  end

  def handle_event("change", params, socket) do
    case target_name(params["_target"]) do
      "preset_save_name" ->
        {:noreply, assign(socket, preset_save_name: params["preset_save_name"] || "")}

      _ ->
        handle_config_change(params, socket)
    end
  end

  def handle_event("overwrite_preset", _params, socket) do
    id = socket.assigns.loaded_preset_id

    cond do
      is_nil(id) or id == "custom" ->
        {:noreply, assign(socket, preset_message: {:error, "No preset loaded to overwrite"})}

      true ->
        attrs = ScenePresets.attrs_from_config(socket.assigns.config)

        case ScenePresets.update(id, attrs) do
          {:ok, _preset} ->
            snapshot = scene_snapshot(socket.assigns.config)

            {:noreply,
             socket
             |> assign(
               presets: ScenePresets.list_all(),
               saved_snapshot: snapshot,
               dirty: false,
               preset_message: {:ok, "Preset updated"}
             )}

          {:error, :builtin} ->
            {:noreply, assign(socket, preset_message: {:error, "Built-in presets cannot be changed"})}

          {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
            {:noreply, assign(socket, preset_message: {:error, preset_error_message(changeset)})}

          {:error, _} ->
            {:noreply, assign(socket, preset_message: {:error, "Could not update preset"})}
        end
    end
  end

  def handle_event("discard_changes", _params, socket) do
    case socket.assigns.saved_snapshot do
      nil ->
        {:noreply, socket}

      snapshot ->
        new_config = merge_scene_config(socket.assigns.config, snapshot)
        :ok = AppSupervisor.update_config(socket.assigns.app_id, new_config)

        {:noreply,
         sync_from_app_config(socket, external: false, snapshot: snapshot)
         |> assign(preset_message: nil)}
    end
  end

  def handle_event("open_save_preset_modal", _params, socket) do
    {:noreply,
     assign(socket, show_save_preset_modal: true, preset_save_name: "", preset_message: nil)}
  end

  def handle_event("close_save_preset_modal", _params, socket) do
    {:noreply, assign(socket, show_save_preset_modal: false, preset_save_name: "")}
  end

  def handle_event("save_preset", params, socket) do
    name =
      (params["preset_save_name"] || socket.assigns.preset_save_name || "")
      |> String.trim()

    cond do
      name == "" ->
        {:noreply, assign(socket, preset_message: {:error, "Enter a preset name"})}

      ScenePresets.validate_formula(socket.assigns.config[:program]) == :error ->
        {:noreply,
         assign(socket,
           show_save_preset_modal: false,
           preset_message: {:error, "Formula is invalid"}
         )}

      true ->
        attrs =
          socket.assigns.config
          |> ScenePresets.attrs_from_config()
          |> Map.put(:name, name)

        case ScenePresets.create(attrs) do
          {:ok, preset} ->
            snapshot = scene_snapshot(preset)
            {:noreply,
             socket
             |> assign(
               presets: ScenePresets.list_all(),
               loaded_preset_id: preset.id,
               active_preset_id: preset.id,
               saved_snapshot: snapshot,
               dirty: false,
               show_save_preset_modal: false,
               preset_save_name: "",
               preset_message: {:ok, "Scene saved"}
             )}

          {:error, changeset} ->
            {:noreply, assign(socket, preset_message: {:error, preset_error_message(changeset)})}
        end
    end
  end

  def handle_event("delete_preset", %{"id" => preset_id}, socket) do
    case ScenePresets.delete(preset_id) do
      :ok ->
        ids = List.delete(socket.assigns.config[:cycle_preset_ids] || [], preset_id)
        loaded_id = socket.assigns.loaded_preset_id

        socket =
          socket
          |> assign(
            presets: ScenePresets.list_all(),
            loaded_preset_id: if(loaded_id == preset_id, do: nil, else: loaded_id),
            saved_snapshot: if(loaded_id == preset_id, do: nil, else: socket.assigns.saved_snapshot),
            preset_message: {:ok, "Preset deleted"}
          )

        socket =
          if ids != (socket.assigns.config[:cycle_preset_ids] || []) do
            new_config = Map.put(socket.assigns.config, :cycle_preset_ids, ids)
            :ok = AppSupervisor.update_config(socket.assigns.app_id, new_config)
            sync_from_app_config(socket, external: false)
          else
            socket
          end

        {:noreply, assign_dirty_state(socket)}

      {:error, :builtin} ->
        {:noreply, assign(socket, preset_message: {:error, "Built-in presets cannot be deleted"})}

      {:error, _} ->
        {:noreply, assign(socket, preset_message: {:error, "Could not delete preset"})}
    end
  end

  defp handle_config_change(params, socket) do
    changed_keys = target_keys(params)

    parsed =
      params
      |> Map.drop(["_target", "preset_save_name"])
      |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_unused_") end)
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Enum.map(fn {key, value} ->
        {key, parse_option(key, value, socket.assigns.config_schema_map)}
      end)
      |> Map.new()

    config =
      changed_keys
      |> Enum.flat_map(fn key ->
        if Map.has_key?(parsed, key), do: [{key, Map.fetch!(parsed, key)}], else: []
      end)
      |> Map.new()

    new_config =
      socket.assigns.config
      |> Map.merge(config)
      |> Map.put(:cycle_preset_ids, socket.assigns.config[:cycle_preset_ids] || [])
      |> Map.put(:cycle_interval_minutes, socket.assigns.config[:cycle_interval_minutes] || 5.0)

    :ok = AppSupervisor.update_config(socket.assigns.app_id, new_config)

    {:noreply, sync_from_app_config(socket, external: false) |> assign_dirty_state()}
  end

  defp push_cycle_config(socket, cycle_preset_ids) do
    new_config =
      socket.assigns.config
      |> Map.put(:cycle_preset_ids, cycle_preset_ids)

    :ok = AppSupervisor.update_config(socket.assigns.app_id, new_config)

    {:noreply, sync_from_app_config(socket, external: true)}
  end

  defp maybe_sync_external_config(socket, true) do
    sync_from_app_config(socket, external: true)
  end

  defp maybe_sync_external_config(socket, _), do: socket

  defp sync_from_app_config(socket, opts) do
    external? = Keyword.get(opts, :external, false)
    preset_id = Keyword.get(opts, :preset_id)
    snapshot = Keyword.get(opts, :snapshot)

    config = AppSupervisor.config(socket.assigns.app_id)
    live_id = live_preset_id(config)

    loaded_preset_id =
      cond do
        preset_id -> preset_id
        external? && live_id != "custom" -> live_id
        true -> socket.assigns[:loaded_preset_id]
      end

    saved_snapshot =
      cond do
        snapshot -> snapshot
        external? && live_id != "custom" -> scene_snapshot(config)
        true -> socket.assigns[:saved_snapshot]
      end

    dirty =
      loaded_preset_id not in [nil, "custom"] &&
        saved_snapshot != nil &&
        !ScenePresets.config_matches?(config, saved_snapshot)

    assign(socket,
      config: config,
      live_preset_id: live_id,
      active_preset_id: live_id,
      loaded_preset_id: loaded_preset_id,
      saved_snapshot: saved_snapshot,
      formula_valid: ScenePresets.validate_formula(config[:program]) == :ok,
      config_info: PixelFun.config_info(config),
      dirty: if(external?, do: false, else: dirty)
    )
  end

  defp assign_dirty_state(socket) do
    dirty =
      socket.assigns.loaded_preset_id not in [nil, "custom"] &&
        socket.assigns.saved_snapshot != nil &&
        !ScenePresets.config_matches?(socket.assigns.config, socket.assigns.saved_snapshot)

    assign(socket, dirty: dirty)
  end

  defp scene_snapshot(%{} = preset_or_config) do
    if Map.has_key?(preset_or_config, :formula) do
      ScenePresets.to_config(preset_or_config)
    else
      Map.take(preset_or_config, @scene_keys)
    end
  end

  defp merge_scene_config(config, scene) do
    Map.merge(config, scene)
  end

  defp scene_entries(config_schema) do
    config_schema
    |> Enum.reject(fn {key, {_name, type, _opts}} ->
      key == :program or type == :internal
    end)
  end

  defp target_name(target) when is_binary(target), do: target
  defp target_name([target | _]), do: target
  defp target_name(_), do: nil

  defp target_keys(%{"_target" => target}) when is_list(target) do
    target |> Enum.flat_map(&schema_key/1)
  end

  defp target_keys(%{"_target" => target}) when is_binary(target), do: schema_key(target)

  defp target_keys(params) do
    params
    |> Map.drop(["_target", "preset_save_name"])
    |> Map.keys()
    |> Enum.flat_map(&schema_key/1)
  end

  defp schema_key(key) do
    [String.to_existing_atom(key)]
  rescue
    ArgumentError -> []
  end

  defp parse_option(key, value, config_schema) do
    type = config_schema |> Map.get(key) |> elem(1)

    case type do
      :float ->
        value |> Float.parse() |> elem(0)

      :int ->
        value |> Integer.parse() |> elem(0)

      :internal when key == :cycle_interval_minutes ->
        value |> Float.parse() |> elem(0)

      type when type in [:string, :internal] ->
        value
    end
  end

  defp preset_error_message(changeset) do
    case changeset.errors do
      [{:name, {msg, _}} | _] -> "Name #{msg}"
      [{:formula, {msg, _}} | _] -> "Formula #{msg}"
      _ -> "Could not save preset"
    end
  end

  defp preset_message_text({:ok, message}), do: message
  defp preset_message_text({:error, message}), do: message

  defp active_preset_id(config) do
    Map.get(config, :active_preset_id) || ScenePresets.id_for_config(config)
  end

  defp live_preset_id(config) when is_map(config) do
    case Map.get(config, :cycle_preset_ids, []) do
      ids when is_list(ids) and length(ids) >= 2 ->
        index = Map.get(config, :cycle_index, 0)
        Enum.at(ids, index) || active_preset_id(config)

      [id] ->
        id

      _ ->
        active_preset_id(config)
    end
  end

  defp live_preset_id(_), do: "custom"

  defp config_changed?(left, right) when is_map(left) and is_map(right) do
    left != right
  end

  defp config_changed?(_, _), do: true

  defp preset_name(presets, id) do
    case Enum.find(presets, &(&1.id == id)) do
      nil -> "Unknown preset"
      preset -> preset.name
    end
  end

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:opts, :map, required: true)
  attr(:value, :any, required: true)

  defp slider_input(assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step={@opts |> Map.get(:step, if(@type == :int, do: 1, else: 0.01))}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce="100"
      value={@value}
      oninput={"if(this.nextElementSibling)this.nextElementSibling.value=this.value"}
      class="range range-primary range-sm flex-grow"
    />
    """
  end

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:opts, :map, required: true)
  attr(:value, :any, required: true)

  defp number_input(assigns) do
    ~H"""
    <input
      type="number"
      name={@key}
      id={"#{@app_id}-#{@key}-number"}
      step={@opts |> Map.get(:step, if(@type == :int, do: 1, else: 0.01))}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce="100"
      value={@value}
      oninput={"if(this.previousElementSibling)this.previousElementSibling.value=this.value"}
      class="input input-bordered input-xs w-20 text-right tabular-nums shrink-0"
    />
    """
  end
end
