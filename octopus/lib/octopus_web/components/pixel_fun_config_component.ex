defmodule OctopusWeb.PixelFunConfigComponent do
  use OctopusWeb, :live_component

  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun
  alias Octopus.Apps.PixelFun.ScenePresets
  alias Octopus.InstallationTransport

  @known_idents ~w(
    x y t i l m h pi tau
    rand random abs sqrt hypot sin cos tan asin acos atan atan2
    asinh acosh atanh floor ceil round fract noise
  )

  def mount(socket) do
    {:ok,
     assign(socket,
       presets: [],
       selected_preset_id: nil,
       preset_message: nil,
       show_save_preset_modal: false,
       preset_save_name: "",
       show_delete_modal: false,
       delete_target_id: nil,
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
    <div data-theme="dark" class="pf-root rounded-xl space-y-4">
      <style>
        .pf-root{font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif}
        .pf-mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,monospace}
      </style>

      <div class="flex flex-wrap items-center gap-3">
        <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← Console</.link>
        <h2 class="text-lg font-semibold flex-1">{@editor_name}</h2>
        <.live_badge :if={@live_preset} />
        <span :if={@queue_position} class="badge badge-outline badge-sm">Nr. {@queue_position}</span>
        <span
          :if={@dirty}
          class="badge gap-1 border-[#fcb700] text-[#fcb700] bg-transparent"
        >
          <span class="w-2 h-2 rounded-full bg-[#fcb700]" /> Unsaved edits
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
              {preset.name}{if preset.builtin, do: "", else: " (yours)"}
            </option>
          </select>
        </div>
      </div>

      <.scene_editor {assigns} />

      <.save_modal :if={@show_save_preset_modal} {assigns} />
      <.delete_modal :if={@show_delete_modal} {assigns} />
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
            <div class="pf-mono text-[11px] opacity-60 mb-1">x y t i · l m h (audio) · pi tau</div>
            <input
              type="text"
              name="program"
              id={"#{@app_id}-program"}
              phx-debounce="150"
              value={@config[:program]}
              class={[
                "input input-bordered w-full pf-mono text-sm",
                !@formula_valid && "border-[#ff6266] focus:border-[#ff6266]"
              ]}
            />
            <p :if={@formula_valid} class="text-xs mt-1 text-[#00d390]">
              ✓ Valid — updating the wall as you type
            </p>
            <p :if={!@formula_valid} class="text-xs mt-1 text-[#ff6266]">
              ✕ Can't read this — '{@formula_error}' isn't a function. The wall keeps the last valid formula.
            </p>
          </div>

          <div :for={{key, {name, type, opts}} <- scene_entries(@config_schema)}>
            <div class="flex items-center justify-between">
              <label class="label-text font-semibold" for={"#{@app_id}-#{key}"}>{name}</label>
              <span class="pf-mono text-sm opacity-80">{format_slider(@config[key])}</span>
            </div>
            <.slider_input app_id={@app_id} key={key} type={type} opts={opts} value={@config[key]} myself={@myself} />
          </div>
        </form>

        <div class="flex flex-wrap gap-2 items-center">
          <button
            class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]"
            phx-click="open_save_preset_modal"
            phx-target={@myself}
            disabled={!@formula_valid}
          >
            Save as new scene…
          </button>
          <button
            :if={@editor_preset && !@editor_preset.builtin}
            class="btn"
            phx-click="overwrite_preset"
            phx-target={@myself}
            disabled={!@formula_valid or !@dirty}
          >
            Overwrite "{@editor_preset.name}"
          </button>
          <button :if={@dirty} class="btn btn-ghost" phx-click="discard_changes" phx-target={@myself}>
            Discard edits
          </button>
          <button
            :if={@editor_preset && !@editor_preset.builtin}
            class="btn btn-ghost text-[#ff6266] ml-auto"
            phx-click="request_delete"
            phx-value-id={@editor_preset.id}
            phx-target={@myself}
          >
            Delete
          </button>
        </div>

        <p :if={@preset_message} class={[
          "text-xs",
          match?({:ok, _}, @preset_message) && "text-[#00d390]",
          match?({:error, _}, @preset_message) && "text-[#ff6266]"
        ]}>
          {preset_message_text(@preset_message)}
        </p>
      </div>
    </div>
    """
  end

  defp save_modal(assigns) do
    ~H"""
    <div class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Save as new scene</h3>
        <form phx-submit="save_preset" phx-target={@myself} class="space-y-4 mt-2">
          <input type="text" name="preset_save_name" value={@preset_save_name} placeholder="Scene name" class="input input-bordered w-full" />
          <div class="modal-action mt-0">
            <button type="button" class="btn btn-ghost" phx-click="close_save_preset_modal" phx-target={@myself}>Cancel</button>
            <button type="submit" class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]" disabled={!@formula_valid}>Save</button>
          </div>
        </form>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_save_preset_modal" phx-target={@myself} />
    </div>
    """
  end

  defp delete_modal(assigns) do
    assigns = assign(assigns, :target, Enum.find(assigns.presets, &(&1.id == assigns.delete_target_id)))

    ~H"""
    <div class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Delete scene</h3>
        <p class="py-2 text-sm opacity-80">
          Delete '{@target && @target.name}'? It's removed from the installation queue too.
        </p>
        <div class="modal-action">
          <button class="btn btn-ghost" phx-click="cancel_delete" phx-target={@myself}>Cancel</button>
          <button class="btn text-[#ff6266]" phx-click="confirm_delete" phx-target={@myself}>Delete</button>
        </div>
      </div>
      <button type="button" class="modal-backdrop" phx-click="cancel_delete" phx-target={@myself} />
    </div>
    """
  end

  defp live_badge(assigns) do
    ~H"""
    <span class="badge badge-sm bg-[#00d390] text-black border-0 font-semibold">LIVE</span>
    """
  end

  attr :app_id, :string, required: true
  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :opts, :map, required: true
  attr :value, :any, required: true
  attr :myself, :any, required: true

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
      class="range range-primary range-sm w-full"
    />
    """
  end

  def handle_event("select_scene", %{"preset_id" => "new"}, socket) do
    {:noreply, assign(socket, selected_preset_id: "new") |> assign_editor_view()}
  end

  def handle_event("select_scene", %{"preset_id" => id}, socket) do
    case ScenePresets.get(id) do
      nil ->
        {:noreply, socket}

      preset ->
        config = ScenePresets.to_config(preset)
        AppSupervisor.update_config(socket.assigns.app_id, config)

        {:noreply,
         socket
         |> assign(config: AppSupervisor.config(socket.assigns.app_id), selected_preset_id: id)
         |> assign_editor_view()}
    end
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

    AppSupervisor.update_config(socket.assigns.app_id, config)

    {:noreply,
     socket
     |> assign(config: AppSupervisor.config(socket.assigns.app_id))
     |> assign_editor_view()}
  end

  def handle_event("open_save_preset_modal", _params, socket),
    do: {:noreply, assign(socket, show_save_preset_modal: true)}

  def handle_event("close_save_preset_modal", _params, socket),
    do: {:noreply, assign(socket, show_save_preset_modal: false, preset_save_name: "")}

  def handle_event("save_preset", params, socket) do
    name = params["preset_save_name"] || socket.assigns.preset_save_name

    case ScenePresets.create(preset_attrs(socket.assigns.config, name)) do
      {:ok, preset} ->
        {:noreply,
         socket
         |> assign(
           presets: ScenePresets.list_all(),
           selected_preset_id: preset.id,
           show_save_preset_modal: false,
           preset_save_name: "",
           preset_message: {:ok, "Scene saved"}
         )
         |> assign_editor_view()}

      {:error, changeset} ->
        {:noreply, assign(socket, preset_message: {:error, preset_error_message(changeset)})}
    end
  end

  def handle_event("overwrite_preset", _params, socket) do
    preset = socket.assigns.editor_preset

    case ScenePresets.update(preset.id, preset_attrs(socket.assigns.config, preset.name)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(presets: ScenePresets.list_all(), preset_message: {:ok, "Scene updated"})
         |> assign_editor_view()}

      {:error, changeset} ->
        {:noreply, assign(socket, preset_message: {:error, preset_error_message(changeset)})}
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

  def handle_event("request_delete", %{"id" => id}, socket),
    do: {:noreply, assign(socket, show_delete_modal: true, delete_target_id: id)}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, show_delete_modal: false, delete_target_id: nil)}

  def handle_event("confirm_delete", _params, socket) do
    id = socket.assigns.delete_target_id

    socket =
      case ScenePresets.delete(id) do
        :ok ->
          remove_from_installation_queue(id)

          assign(socket,
            presets: ScenePresets.list_all(),
            preset_message: {:ok, "Scene deleted"},
            selected_preset_id: nil
          )

        {:error, :builtin} ->
          assign(socket, preset_message: {:error, "Built-in scenes can't be deleted"})

        {:error, _} ->
          assign(socket, preset_message: {:error, "Could not delete scene"})
      end

    {:noreply, assign(socket, show_delete_modal: false, delete_target_id: nil) |> assign_editor_view()}
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

  defp remove_from_installation_queue(scene_id) do
    transport = InstallationTransport.get_state()

    new_queue =
      Enum.reject(transport.queue, fn entry ->
        entry.app == PixelFun and entry.mode_id == scene_id
      end)

    InstallationTransport.set_queue(
      Enum.map(new_queue, fn e -> %{app: e.app, mode_id: e.mode_id} end)
    )
  end

  defp preset_attrs(config, name) do
    %{
      name: name,
      formula: config[:program],
      color_interval: config[:color_interval],
      translate_scale: config[:translate_scale],
      rotate_scale: config[:rotate_scale],
      zoom_scale: config[:zoom_scale]
    }
  end

  defp scene_entries(config_schema) do
    Enum.reject(config_schema, fn {key, {_name, type, _opts}} ->
      key == :program or type == :internal
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

  defp preset_error_message(changeset) do
    case changeset.errors do
      [{:name, {msg, _}} | _] -> "Name #{msg}"
      [{:formula, {msg, _}} | _] -> "Formula #{msg}"
      _ -> "Could not save scene"
    end
  end

  defp preset_message_text({:ok, message}), do: message
  defp preset_message_text({:error, message}), do: message
end
