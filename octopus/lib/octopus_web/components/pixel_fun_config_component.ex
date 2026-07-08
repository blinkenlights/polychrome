defmodule OctopusWeb.PixelFunConfigComponent do
  use OctopusWeb, :live_component

  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun
  alias Octopus.Apps.PixelFun.ScenePresets

  @interval_presets [
    {"30 s", 30},
    {"1 min", 60},
    {"5 min", 300},
    {"15 min", 900},
    {"1 h", 3600}
  ]

  # Variables and functions understood by the formula parser — used to build the
  # "'{token}' isn't a function" hint and the editor legend.
  @known_idents ~w(
    x y t i l m h pi tau
    rand random abs sqrt hypot sin cos tan asin acos atan atan2
    asinh acosh atanh floor ceil round fract noise
  )

  def mount(socket) do
    {:ok,
     assign(socket,
       presets: [],
       now_ms: System.os_time(:millisecond),
       active_tab: "queue",
       new_scene: false,
       preset_message: nil,
       show_save_preset_modal: false,
       preset_save_name: "",
       show_delete_modal: false,
       delete_target_id: nil,
       show_custom_interval_modal: false,
       config_info: nil,
       config: %{}
     )}
  end

  def update(%{app_module: PixelFun} = assigns, socket) do
    socket = assign(socket, assigns)

    config =
      cond do
        is_map(assigns[:config]) -> assigns[:config]
        is_map(socket.assigns[:config]) and map_size(socket.assigns.config) > 0 -> socket.assigns.config
        true -> AppSupervisor.config(assigns.app_id)
      end

    {:ok,
     socket
     |> assign(
       config: config,
       config_schema: PixelFun.config_schema(),
       config_schema_map: PixelFun.config_schema() |> Map.new(),
       presets: ScenePresets.list_all(),
       config_info: PixelFun.config_info(config)
     )}
  end

  # Partial updates (e.g. the 1-second countdown tick carrying only now_ms).
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def render(assigns) do
    assigns = assign_view(assigns)

    ~H"""
    <div data-theme="dark" class="pf-root rounded-xl">
      <style>
        .pf-root{font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif}
        .pf-mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,monospace}
      </style>

      <%!-- ===================== DESKTOP / NARROW (>=700px) ===================== --%>
      <div class="hidden min-[700px]:block space-y-6">
        <.transport_bar {assigns} />

        <div class="grid gap-6 min-[1100px]:grid-cols-2 min-[1100px]:items-start">
          <div class="min-[1100px]:col-start-1 min-[1100px]:row-start-1 min-[1100px]:row-span-2 order-2 min-[1100px]:order-none">
            <.scene_library {assigns} />
          </div>
          <div class="min-[1100px]:col-start-2 min-[1100px]:row-start-1 order-1 min-[1100px]:order-none">
            <.queue_card {assigns} />
          </div>
          <div class="min-[1100px]:col-start-2 min-[1100px]:row-start-2 order-3 min-[1100px]:order-none">
            <.scene_editor {assigns} />
          </div>
        </div>
      </div>

      <%!-- ===================== MOBILE (<700px) ===================== --%>
      <div class="min-[700px]:hidden">
        <.mini_transport {assigns} />

        <div role="tablist" class="tabs tabs-boxed my-4">
          <button
            :for={{id, label} <- [{"queue", "Queue"}, {"library", "Library"}, {"editor", "Editor"}]}
            role="tab"
            class={["tab min-h-11", @active_tab == id && "tab-active"]}
            phx-click="select_tab"
            phx-value-tab={id}
            phx-target={@myself}
          >
            {label}
            <span
              :if={id == "editor" and @dirty}
              class="ml-1 inline-block w-2 h-2 rounded-full bg-[#fcb700]"
            />
          </button>
        </div>

        <div class={@active_tab != "queue" && "hidden"}><.queue_card {assigns} /></div>
        <div class={@active_tab != "library" && "hidden"}><.scene_library {assigns} /></div>
        <div class={@active_tab != "editor" && "hidden"}><.scene_editor {assigns} /></div>
      </div>

      <.save_modal :if={@show_save_preset_modal} {assigns} />
      <.delete_modal :if={@show_delete_modal} {assigns} />
      <.custom_interval_modal :if={@show_custom_interval_modal} {assigns} />
    </div>
    """
  end

  # ------------------------------------------------------------------ views ---

  defp transport_bar(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-4 gap-4">
        <div class="flex items-center gap-4 flex-wrap">
          <.transport_controls {assigns} />

          <div class="flex-1 min-w-[12rem]">
            <div class="text-[11px] uppercase tracking-wide opacity-60">Now on the wall</div>
            <div class="flex items-center gap-2">
              <span class="text-lg font-semibold">{@live_name}</span>
              <.live_badge :if={@live_preset} />
            </div>
            <div class="text-sm opacity-70">
              <%= if @rotating? do %>
                Next: {@next_name} · scene {@live_pos_label} of {@count}
              <% else %>
                {@holding_subtitle}
              <% end %>
            </div>
          </div>

          <.countdown_ring :if={@rotating?} {assigns} />
        </div>

        <div>
          <.interval_picker {assigns} />
          <p class="text-xs opacity-60 mt-1">
            Applies at the next change — the running countdown isn't reset.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp mini_transport(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-3 flex-row items-center gap-3">
        <button
          class="btn btn-circle btn-primary btn-sm w-11 h-11"
          phx-click="toggle_play"
          phx-target={@myself}
          aria-label={if @playing, do: "Pause", else: "Play"}
        >
          {if @playing, do: "❚❚", else: "▶"}
        </button>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-semibold truncate">{@live_name}</span>
            <.live_badge :if={@live_preset} />
          </div>
          <div class="text-xs opacity-70 truncate">
            <%= if @rotating?, do: "Next: #{@next_name}", else: @holding_subtitle %>
          </div>
        </div>
        <.countdown_ring :if={@rotating?} {assigns} />
      </div>
    </div>
    """
  end

  defp transport_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <button
        class="btn btn-circle btn-ghost w-11 h-11"
        phx-click="prev"
        phx-target={@myself}
        disabled={!@rotating?}
        aria-label="Previous scene"
      >
        ⏮
      </button>
      <button
        class="btn btn-circle btn-primary bg-[#6d7cff] border-[#6d7cff] hover:bg-[#5b6aff] w-14 h-14 text-lg"
        phx-click="toggle_play"
        phx-target={@myself}
        aria-label={if @playing, do: "Pause", else: "Play"}
      >
        {if @playing, do: "❚❚", else: "▶"}
      </button>
      <button
        class="btn btn-circle btn-ghost w-11 h-11"
        phx-click="next"
        phx-target={@myself}
        disabled={!@rotating?}
        aria-label="Next scene"
      >
        ⏭
      </button>
    </div>
    """
  end

  defp countdown_ring(assigns) do
    ~H"""
    <div
      class={[
        "radial-progress pf-mono text-sm shrink-0",
        @playing && "text-[#00d390]",
        !@playing && "opacity-40"
      ]}
      style={"--value:#{@countdown_percent}; --size:3.25rem; --thickness:3px;"}
      role="timer"
      aria-label="Time until next scene"
    >
      {@countdown_label}
    </div>
    """
  end

  defp interval_picker(assigns) do
    ~H"""
    <div>
      <div class="text-[11px] uppercase tracking-wide opacity-60 mb-1">Change scene every</div>
      <div class="join">
        <button
          :for={{label, seconds} <- interval_presets()}
          class={[
            "btn btn-sm join-item min-h-11",
            @interval_seconds == seconds && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
          ]}
          phx-click="set_interval"
          phx-value-seconds={seconds}
          phx-target={@myself}
        >
          {label}
        </button>
        <button
          class={[
            "btn btn-sm join-item min-h-11",
            @interval_custom? && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
          ]}
          phx-click="open_custom_interval"
          phx-target={@myself}
          aria-label="Custom interval"
        >
          …
        </button>
      </div>
    </div>
    """
  end

  defp scene_library(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-3">
        <div class="flex items-center justify-between">
          <h2 class="text-base font-semibold">Scene library</h2>
          <span class="text-xs opacity-60">
            {@builtin_count} built-in · {@user_count} yours
          </span>
        </div>

        <div class="grid grid-cols-1 min-[700px]:grid-cols-2 gap-3">
          <.scene_tile :for={preset <- @presets} preset={preset} myself={@myself} live_id={@live_id} queue_ids={@queue_ids} />

          <button
            class="card border-2 border-dashed border-base-content/20 hover:border-primary min-h-[7rem] flex items-center justify-center text-center p-3 text-sm opacity-70 hover:opacity-100"
            phx-click="new_scene"
            phx-target={@myself}
          >
            ＋ New scene — starts from what's on the wall
          </button>
        </div>

        <p class="text-xs opacity-60">
          Built-in scenes are read-only — edit one and 'Save as new' to keep it.
        </p>
      </div>
    </div>
    """
  end

  attr :preset, :map, required: true
  attr :myself, :any, required: true
  attr :live_id, :string, required: true
  attr :queue_ids, :list, required: true

  defp scene_tile(assigns) do
    assigns =
      assigns
      |> assign(:live?, assigns.preset.id == assigns.live_id)
      |> assign(:queued_pos, queue_position(assigns.queue_ids, assigns.preset.id))

    ~H"""
    <div class="card bg-base-100 border border-base-300 overflow-hidden">
      <div class="h-1" style={"background-color: #{@preset.accent_color}"} />
      <div class="card-body p-3 gap-2">
        <div class="flex items-start justify-between gap-2">
          <h3 class="font-semibold text-sm leading-tight">{@preset.name}</h3>
          <div class="flex items-center gap-1 shrink-0">
            <.live_badge :if={@live?} />
            <span :if={@queued_pos} class="badge badge-outline badge-sm">Nr. {@queued_pos}</span>
            <span :if={!@preset.builtin} class="badge badge-outline badge-sm opacity-70">yours</span>
          </div>
        </div>

        <p class="pf-mono text-xs opacity-70 truncate" title={@preset.formula}>{@preset.formula}</p>

        <div class="flex gap-2 mt-1">
          <button
            class="btn btn-sm flex-1 min-h-11"
            phx-click="play_now"
            phx-value-id={@preset.id}
            phx-target={@myself}
          >
            ▶ Play now
          </button>
          <button
            class={[
              "btn btn-sm flex-1 min-h-11",
              @queued_pos && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
            ]}
            phx-click="queue_toggle"
            phx-value-id={@preset.id}
            phx-target={@myself}
          >
            {if @queued_pos, do: "✓ Queued", else: "＋ Queue"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp queue_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-3">
        <div class="flex items-center justify-between">
          <h2 class="text-base font-semibold">Queue</h2>
          <span class="text-xs opacity-60">
            <%= if @count == 0 do %>
              empty
            <% else %>
              {@count} {ngettext("scene", "scenes", @count)} · every {@interval_label}
            <% end %>
          </span>
        </div>

        <div :if={@count == 0} class="border-2 border-dashed border-base-content/20 rounded-lg p-6 text-center text-sm opacity-70">
          <div class="font-semibold mb-1">Nothing queued</div>
          The wall keeps showing {@live_name}. Add scenes with ＋ Queue to rotate through them.
        </div>

        <div :if={@count > 0} class="flex flex-col gap-2">
          <.queue_row
            :for={{{id, preset}, idx} <- Enum.with_index(@queue)}
            id={id}
            preset={preset}
            idx={idx}
            count={@count}
            live_id={@live_id}
            up_next_id={@next_id}
            elapsed_percent={@elapsed_percent}
            countdown_label={@countdown_label}
            myself={@myself}
          />
        </div>

        <p :if={@count == 1} class="text-xs opacity-60">
          One scene holds steady — add another to start rotating.
        </p>
        <p :if={@count > 1} class="text-xs opacity-60">
          Reorder with the arrows — the wall follows this order, top to bottom, then repeats.
        </p>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :preset, :any, required: true
  attr :idx, :integer, required: true
  attr :count, :integer, required: true
  attr :live_id, :string, required: true
  attr :up_next_id, :any, required: true
  attr :elapsed_percent, :any, required: true
  attr :countdown_label, :string, required: true
  attr :myself, :any, required: true

  defp queue_row(assigns) do
    assigns =
      assigns
      |> assign(:live?, assigns.id == assigns.live_id)
      |> assign(:up_next?, assigns.id == assigns.up_next_id)
      |> assign(:name, (assigns.preset && assigns.preset.name) || "Unknown scene")
      |> assign(:accent, (assigns.preset && assigns.preset.accent_color) || "#2a323c")

    ~H"""
    <div class={[
      "relative flex items-center gap-2 rounded-lg border p-2 pf-mono-off overflow-hidden",
      @live? && "border-[#00d390] bg-[#00d390]/10",
      !@live? && "border-base-300 bg-base-100"
    ]}>
      <span class="w-5 text-center text-xs opacity-60">{@idx + 1}</span>
      <span class="w-1 h-6 rounded" style={"background-color: #{@accent}"} />
      <span class="flex-1 font-semibold text-sm truncate">{@name}</span>

      <.live_badge :if={@live?} />
      <span
        :if={@up_next? and not @live?}
        class="badge badge-outline badge-sm"
      >
        up next · {@countdown_label}
      </span>

      <div class="flex items-center gap-1">
        <button
          class="btn btn-ghost btn-xs btn-square w-8 h-8"
          phx-click="queue_move"
          phx-value-id={@id}
          phx-value-dir="up"
          phx-target={@myself}
          disabled={@idx == 0}
          aria-label="Move up"
        >
          ▲
        </button>
        <button
          class="btn btn-ghost btn-xs btn-square w-8 h-8"
          phx-click="queue_move"
          phx-value-id={@id}
          phx-value-dir="down"
          phx-target={@myself}
          disabled={@idx == @count - 1}
          aria-label="Move down"
        >
          ▼
        </button>
        <button
          class="btn btn-ghost btn-xs btn-square w-8 h-8"
          phx-click="queue_remove"
          phx-value-id={@id}
          phx-target={@myself}
          aria-label="Remove from queue"
        >
          ✕
        </button>
      </div>

      <div
        :if={@live?}
        class="absolute bottom-0 left-0 h-[3px] bg-[#00d390]"
        style={"width: #{@elapsed_percent}%"}
      />
    </div>
    """
  end

  defp scene_editor(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-4">
        <div class="flex items-center gap-2 flex-wrap">
          <.live_badge :if={@live_preset} />
          <span class="font-semibold">{@editor_name}</span>
          <span
            :if={@dirty}
            class="badge gap-1 border-[#fcb700] text-[#fcb700] bg-transparent"
          >
            <span class="w-2 h-2 rounded-full bg-[#fcb700]" /> Unsaved edits
          </span>
        </div>

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
          <div :if={@editor_preset && @editor_preset.builtin} class="tooltip" data-tip="Built-in — can't overwrite">
            <button class="btn" disabled>Overwrite "{@editor_preset.name}"</button>
          </div>
          <button
            :if={@dirty}
            class="btn btn-ghost"
            phx-click="discard_changes"
            phx-target={@myself}
          >
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

  # ----------------------------------------------------------------- modals ---

  defp save_modal(assigns) do
    ~H"""
    <div class="modal modal-open" role="dialog" aria-modal="true">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Save as new scene</h3>
        <p class="py-2 text-sm opacity-70">Save the current formula and slider values under a new name.</p>
        <form phx-submit="save_preset" phx-target={@myself} class="space-y-4" id={"#{@app_id}-save-form"}>
          <input
            type="text"
            name="preset_save_name"
            value={@preset_save_name}
            placeholder="Scene name"
            autofocus
            class="input input-bordered w-full"
          />
          <div class="modal-action mt-0">
            <button type="button" class="btn btn-ghost" phx-click="close_save_preset_modal" phx-target={@myself}>
              Cancel
            </button>
            <button type="submit" class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]" disabled={!@formula_valid}>
              Save
            </button>
          </div>
        </form>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_save_preset_modal" phx-target={@myself} aria-label="Close" />
    </div>
    """
  end

  defp delete_modal(assigns) do
    assigns = assign(assigns, :target, Enum.find(assigns.presets, &(&1.id == assigns.delete_target_id)))

    ~H"""
    <div class="modal modal-open" role="dialog" aria-modal="true">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Delete scene</h3>
        <p class="py-2 text-sm opacity-80">
          Delete '{@target && @target.name}'? It's removed from the queue too. This can't be undone.
        </p>
        <div class="modal-action">
          <button class="btn btn-ghost" phx-click="cancel_delete" phx-target={@myself}>Cancel</button>
          <button class="btn text-[#ff6266]" phx-click="confirm_delete" phx-target={@myself}>Delete</button>
        </div>
      </div>
      <button type="button" class="modal-backdrop" phx-click="cancel_delete" phx-target={@myself} aria-label="Close" />
    </div>
    """
  end

  defp custom_interval_modal(assigns) do
    ~H"""
    <div class="modal modal-open" role="dialog" aria-modal="true">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Custom interval</h3>
        <form phx-submit="save_custom_interval" phx-target={@myself} class="space-y-4 mt-2" id={"#{@app_id}-interval-form"}>
          <div class="flex gap-2">
            <input type="number" name="value" min="1" step="1" value="1" class="input input-bordered flex-1" />
            <select name="unit" class="select select-bordered">
              <option value="s">seconds</option>
              <option value="min" selected>minutes</option>
              <option value="h">hours</option>
            </select>
          </div>
          <div class="modal-action mt-0">
            <button type="button" class="btn btn-ghost" phx-click="close_custom_interval" phx-target={@myself}>
              Cancel
            </button>
            <button type="submit" class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]">Set</button>
          </div>
        </form>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_custom_interval" phx-target={@myself} aria-label="Close" />
    </div>
    """
  end

  defp live_badge(assigns) do
    ~H"""
    <span class="badge badge-sm bg-[#00d390] text-black border-0 font-semibold">LIVE</span>
    """
  end

  # -------------------------------------------------------------- view calc ---

  defp assign_view(assigns) do
    config = assigns.config
    presets = assigns.presets
    by_id = Map.new(presets, &{&1.id, &1})

    queue_ids = List.wrap(config[:cycle_preset_ids])
    count = length(queue_ids)
    interval_seconds = trunc(config[:cycle_interval_seconds] || 300)
    cycle_index = config[:cycle_index] || 0
    playing = config[:playing] != false
    next_at = config[:next_change_at_ms]
    now = assigns.now_ms

    live_id =
      cond do
        assigns.new_scene -> "custom"
        is_binary(config[:live_scene_id]) -> config[:live_scene_id]
        true -> ScenePresets.id_for_config(config)
      end

    live_preset = by_id[live_id]
    rotating? = count >= 2

    remaining_ms =
      cond do
        !rotating? -> nil
        # Frozen countdown while paused.
        !playing and is_integer(config[:paused_remaining_ms]) -> config[:paused_remaining_ms]
        !playing -> nil
        is_integer(next_at) -> max(next_at - now, 0)
        true -> nil
      end

    interval_ms = interval_seconds * 1000

    countdown_percent =
      case remaining_ms do
        nil -> 0
        ms when interval_ms > 0 -> round(ms / interval_ms * 100)
        _ -> 0
      end

    elapsed_percent = 100 - countdown_percent

    live_pos = Enum.find_index(queue_ids, &(&1 == live_id))

    next_index = if rotating?, do: rem(cycle_index + 1, count), else: nil
    next_id = next_index && Enum.at(queue_ids, next_index)
    next_preset = next_id && by_id[next_id]

    editor_preset = if assigns.new_scene, do: nil, else: live_preset
    dirty = not is_nil(editor_preset) and not ScenePresets.config_matches?(config, editor_preset)
    formula_valid = ScenePresets.validate_formula(config[:program] || "") == :ok

    assign(assigns,
      queue_ids: queue_ids,
      queue: Enum.map(queue_ids, fn id -> {id, by_id[id]} end),
      count: count,
      interval_seconds: interval_seconds,
      interval_label: interval_label(interval_seconds),
      interval_custom?: not Enum.any?(interval_presets(), fn {_l, s} -> s == interval_seconds end),
      playing: playing,
      rotating?: rotating?,
      live_id: live_id,
      live_preset: live_preset,
      live_name: (live_preset && live_preset.name) || "—",
      live_pos_label: (live_pos && live_pos + 1) || 1,
      next_id: next_id,
      next_name: (next_preset && next_preset.name) || "—",
      countdown_percent: countdown_percent,
      elapsed_percent: elapsed_percent,
      countdown_label: format_mmss(remaining_ms),
      holding_subtitle: holding_subtitle(playing, count, live_preset && live_preset.name),
      editor_preset: editor_preset,
      editor_name: (editor_preset && editor_preset.name) || "New scene",
      dirty: dirty,
      formula_valid: formula_valid,
      formula_error: formula_error_token(config[:program] || ""),
      builtin_count: Enum.count(presets, & &1.builtin),
      user_count: Enum.count(presets, &(!&1.builtin))
    )
  end

  defp holding_subtitle(false, _count, _name), do: "Paused — holding this scene."
  defp holding_subtitle(_playing, count, _name) when count >= 2, do: nil
  defp holding_subtitle(_playing, _count, _name), do: "Holding this scene — add more to rotate."

  # ---------------------------------------------------------------- events ----

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("toggle_play", _params, socket) do
    PixelFun.toggle_play(socket.assigns.app_id)
    {:noreply, socket}
  end

  def handle_event("next", _params, socket) do
    PixelFun.next_scene(socket.assigns.app_id)
    {:noreply, socket}
  end

  def handle_event("prev", _params, socket) do
    PixelFun.prev_scene(socket.assigns.app_id)
    {:noreply, socket}
  end

  def handle_event("play_now", %{"id" => id}, socket) do
    PixelFun.play_now(socket.assigns.app_id, id)
    {:noreply, assign(socket, new_scene: false, preset_message: nil)}
  end

  def handle_event("queue_toggle", %{"id" => id}, socket) do
    ids = current_queue(socket)

    new_ids = if id in ids, do: List.delete(ids, id), else: ids ++ [id]
    PixelFun.set_queue(socket.assigns.app_id, new_ids)
    {:noreply, socket}
  end

  def handle_event("queue_remove", %{"id" => id}, socket) do
    PixelFun.set_queue(socket.assigns.app_id, List.delete(current_queue(socket), id))
    {:noreply, socket}
  end

  def handle_event("queue_move", %{"id" => id, "dir" => dir}, socket) do
    PixelFun.set_queue(socket.assigns.app_id, move(current_queue(socket), id, dir))
    {:noreply, socket}
  end

  def handle_event("set_interval", %{"seconds" => seconds}, socket) do
    PixelFun.set_interval(socket.assigns.app_id, parse_number(seconds))
    {:noreply, socket}
  end

  def handle_event("open_custom_interval", _params, socket) do
    {:noreply, assign(socket, show_custom_interval_modal: true)}
  end

  def handle_event("close_custom_interval", _params, socket) do
    {:noreply, assign(socket, show_custom_interval_modal: false)}
  end

  def handle_event("save_custom_interval", %{"value" => value, "unit" => unit}, socket) do
    seconds =
      case parse_number(value) do
        n when is_number(n) ->
          factor = %{"s" => 1, "min" => 60, "h" => 3600} |> Map.get(unit, 1)
          max(n * factor, 1)

        _ ->
          nil
      end

    if seconds, do: PixelFun.set_interval(socket.assigns.app_id, seconds)
    {:noreply, assign(socket, show_custom_interval_modal: false)}
  end

  def handle_event("new_scene", _params, socket) do
    {:noreply, assign(socket, new_scene: true, active_tab: "editor", preset_message: nil)}
  end

  def handle_event("change", params, socket) do
    changed = target_keys(params)

    scene =
      params
      |> Map.take(Enum.map(scene_keys(), &Atom.to_string/1))
      |> Enum.filter(fn {k, _v} -> String.to_existing_atom(k) in changed end)
      |> Enum.map(fn {k, v} ->
        key = String.to_existing_atom(k)
        {key, parse_option(key, v, socket.assigns.config_schema_map)}
      end)
      |> Map.new()

    if map_size(scene) > 0 do
      AppSupervisor.update_config(socket.assigns.app_id, scene)
    end

    {:noreply, socket}
  end

  def handle_event("open_save_preset_modal", _params, socket) do
    {:noreply, assign(socket, show_save_preset_modal: true, preset_save_name: "", preset_message: nil)}
  end

  def handle_event("close_save_preset_modal", _params, socket) do
    {:noreply, assign(socket, show_save_preset_modal: false)}
  end

  def handle_event("save_preset", params, socket) do
    name = (params["preset_save_name"] || "") |> String.trim()
    config = socket.assigns.config

    cond do
      name == "" ->
        {:noreply, assign(socket, preset_message: {:error, "Enter a scene name"})}

      ScenePresets.validate_formula(config[:program]) == :error ->
        {:noreply, assign(socket, show_save_preset_modal: false, preset_message: {:error, "Formula is invalid"})}

      true ->
        attrs = config |> ScenePresets.attrs_from_config() |> Map.put(:name, name)

        case ScenePresets.create(attrs) do
          {:ok, preset} ->
            PixelFun.play_now(socket.assigns.app_id, preset.id)

            {:noreply,
             assign(socket,
               presets: ScenePresets.list_all(),
               new_scene: false,
               show_save_preset_modal: false,
               preset_save_name: "",
               preset_message: {:ok, "Scene saved"}
             )}

          {:error, changeset} ->
            {:noreply, assign(socket, preset_message: {:error, preset_error_message(changeset)})}
        end
    end
  end

  def handle_event("overwrite_preset", _params, socket) do
    case socket.assigns.config[:live_scene_id] do
      "builtin:" <> _ ->
        {:noreply, assign(socket, preset_message: {:error, "Built-in scenes can't be overwritten"})}

      id when is_binary(id) ->
        attrs = ScenePresets.attrs_from_config(socket.assigns.config)

        case ScenePresets.update(id, attrs) do
          {:ok, _preset} ->
            {:noreply, assign(socket, presets: ScenePresets.list_all(), preset_message: {:ok, "Scene updated"})}

          {:error, :builtin} ->
            {:noreply, assign(socket, preset_message: {:error, "Built-in scenes can't be overwritten"})}

          {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
            {:noreply, assign(socket, preset_message: {:error, preset_error_message(changeset)})}

          {:error, _} ->
            {:noreply, assign(socket, preset_message: {:error, "Could not update scene"})}
        end

      _ ->
        {:noreply, assign(socket, preset_message: {:error, "No scene loaded to overwrite"})}
    end
  end

  def handle_event("discard_changes", _params, socket) do
    case ScenePresets.get(socket.assigns.config[:live_scene_id]) do
      nil ->
        {:noreply, socket}

      preset ->
        AppSupervisor.update_config(socket.assigns.app_id, ScenePresets.to_config(preset))
        {:noreply, assign(socket, preset_message: nil)}
    end
  end

  def handle_event("request_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, show_delete_modal: true, delete_target_id: id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_target_id: nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    id = socket.assigns.delete_target_id

    socket =
      case ScenePresets.delete(id) do
        :ok ->
          PixelFun.set_queue(socket.assigns.app_id, List.delete(current_queue(socket), id))

          assign(socket,
            presets: ScenePresets.list_all(),
            preset_message: {:ok, "Scene deleted"}
          )

        {:error, :builtin} ->
          assign(socket, preset_message: {:error, "Built-in scenes can't be deleted"})

        {:error, _} ->
          assign(socket, preset_message: {:error, "Could not delete scene"})
      end

    {:noreply, assign(socket, show_delete_modal: false, delete_target_id: nil)}
  end

  # ---------------------------------------------------------------- helpers ---

  defp interval_presets, do: @interval_presets

  defp current_queue(socket), do: List.wrap(socket.assigns.config[:cycle_preset_ids])

  defp move(ids, id, dir) do
    case Enum.find_index(ids, &(&1 == id)) do
      nil ->
        ids

      index ->
        swap = if dir == "up", do: index - 1, else: index + 1

        if swap >= 0 and swap < length(ids) do
          a = Enum.at(ids, index)
          b = Enum.at(ids, swap)

          ids
          |> List.replace_at(index, b)
          |> List.replace_at(swap, a)
        else
          ids
        end
    end
  end

  defp queue_position(ids, id), do: queue_position(ids, id, 1)
  defp queue_position([id | _], id, pos), do: pos
  defp queue_position([_ | rest], id, pos), do: queue_position(rest, id, pos + 1)
  defp queue_position([], _id, _pos), do: nil

  defp scene_keys, do: [:program, :color_interval, :translate_scale, :rotate_scale, :zoom_scale]

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

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_number(value) when is_number(value), do: value
  defp parse_number(_), do: nil

  defp format_mmss(nil), do: "--:--"

  defp format_mmss(ms) when is_integer(ms) do
    total = div(ms, 1000)
    minutes = div(total, 60)
    seconds = rem(total, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  defp format_slider(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp format_slider(value) when is_integer(value), do: Integer.to_string(value)
  defp format_slider(value), do: to_string(value)

  defp interval_label(seconds) do
    case Enum.find(interval_presets(), fn {_l, s} -> s == seconds end) do
      {label, _} -> label
      nil -> humanize_interval(seconds)
    end
  end

  defp humanize_interval(seconds) do
    cond do
      rem(seconds, 3600) == 0 -> "#{div(seconds, 3600)} h"
      rem(seconds, 60) == 0 -> "#{div(seconds, 60)} min"
      true -> "#{seconds} s"
    end
  end

  defp formula_error_token(formula) do
    case ScenePresets.validate_formula(formula) do
      :ok ->
        nil

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

  # ---------------------------------------------------------------- inputs ---

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
end
