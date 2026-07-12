defmodule OctopusWeb.ConsoleComponents do
  @moduledoc false
  use OctopusWeb, :html

  alias Octopus.Apps.PixelFun.ScenePresets

  @known_formula_idents ~w(
    x y t i l m h pi PI tau Tau
    rand random abs sqrt exp log hypot sin cos tan asin acos atan atan2
    asinh acosh atanh sinh cosh tanh floor ceil round fract noise
  )

  @interval_presets [
    {"30 s", 30},
    {"1 min", 60},
    {"5 min", 300},
    {"15 min", 900},
    {"1 h", 3600}
  ]

  def interval_presets, do: @interval_presets

  attr :playing, :boolean, required: true
  attr :rotating?, :boolean, required: true
  attr :takeover?, :boolean, default: false
  attr :live_label, :string, required: true
  attr :live?, :boolean, default: false
  attr :transport_mode, :atom, required: true
  attr :subtitle, :string, required: true
  attr :countdown_percent, :integer, required: true
  attr :countdown_label, :string, required: true
  attr :interval_seconds, :integer, required: true
  attr :interval_custom?, :boolean, required: true
  attr :target, :any, default: nil

  def transport_bar(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-4 gap-4">
        <div class="flex items-center gap-4 flex-wrap">
          <.transport_controls rotating?={@rotating?} takeover?={@takeover?} target={@target} playing={@playing} />

          <div class="flex-1 min-w-[12rem]">
            <div class="text-[11px] uppercase tracking-wide opacity-60">Now on the wall</div>
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-lg font-semibold">{@live_label}</span>
              <.transport_mode_badge mode={@transport_mode} />
            </div>
            <div class="text-sm opacity-70">{@subtitle}</div>
          </div>

          <.countdown_ring
            :if={@rotating?}
            playing={@playing}
            countdown_percent={@countdown_percent}
            countdown_label={@countdown_label}
          />
        </div>

        <div>
          <.interval_picker
            interval_seconds={@interval_seconds}
            interval_custom?={@interval_custom?}
            target={@target}
          />
          <p class="text-xs opacity-60 mt-1">
            Applies at the next change — the running countdown isn't reset.
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :playing, :boolean, required: true
  attr :rotating?, :boolean, required: true
  attr :takeover?, :boolean, default: false
  attr :live_label, :string, required: true
  attr :live?, :boolean, default: false
  attr :transport_mode, :atom, required: true
  attr :subtitle, :string, required: true
  attr :countdown_percent, :integer, required: true
  attr :countdown_label, :string, required: true
  attr :target, :any, default: nil

  def mini_transport(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-3 flex-row items-center gap-3">
        <.transport_controls
          rotating?={@rotating?}
          takeover?={@takeover?}
          target={@target}
          playing={@playing}
          compact
        />
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="font-semibold truncate">{@live_label}</span>
            <.transport_mode_badge mode={@transport_mode} />
          </div>
          <div class="text-xs opacity-70 truncate">{@subtitle}</div>
        </div>
        <.countdown_ring
          :if={@rotating?}
          playing={@playing}
          countdown_percent={@countdown_percent}
          countdown_label={@countdown_label}
        />
      </div>
    </div>
    """
  end

  attr :rotating?, :boolean, required: true
  attr :playing, :boolean, required: true
  attr :takeover?, :boolean, default: false
  attr :compact, :boolean, default: false
  attr :target, :any, default: nil

  def transport_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <button
        class="btn btn-circle btn-ghost w-11 h-11"
        phx-click="prev"
        phx-target={@target}
        disabled={!@rotating?}
        aria-label="Previous"
      >
        ⏮
      </button>
      <button
        :if={@takeover?}
        class={[
          "btn btn-error btn-square",
          @compact && "btn-sm w-11 h-11",
          !@compact && "w-11 h-11"
        ]}
        phx-click="resume_rotation"
        phx-target={@target}
        title="Stop"
        aria-label="Stop"
      >
        ■
      </button>
      <button
        :if={@takeover?}
        class={[
          "btn btn-primary bg-[#6d7cff] border-[#6d7cff] hover:bg-[#5b6aff]",
          @compact && "btn-sm btn-circle w-11 h-11 text-xs",
          !@compact && "min-h-14 px-4"
        ]}
        phx-click="resume_rotation"
        phx-target={@target}
        aria-label="Resume playlist"
      >
        {if @compact, do: "↩", else: "Resume playlist"}
      </button>
      <button
        :if={!@takeover?}
        class={[
          "btn btn-circle btn-primary bg-[#6d7cff] border-[#6d7cff] hover:bg-[#5b6aff] text-lg",
          @compact && "btn-sm w-11 h-11",
          !@compact && "w-14 h-14"
        ]}
        phx-click="toggle_play"
        phx-target={@target}
        aria-label={if @playing, do: "Pause", else: "Play"}
      >
        {if @playing, do: "❚❚", else: "▶"}
      </button>
      <button
        class="btn btn-circle btn-ghost w-11 h-11"
        phx-click="next"
        phx-target={@target}
        disabled={!@rotating?}
        aria-label="Next"
      >
        ⏭
      </button>
    </div>
    """
  end

  attr :mode, :atom, required: true

  def transport_mode_badge(assigns) do
    ~H"""
    <span
      :if={@mode != :idle}
      class={[
        "badge badge-sm border-0 font-semibold uppercase tracking-wide",
        @mode == :rotating && "bg-[#00d390] text-black",
        @mode == :takeover && "bg-warning text-warning-content",
        @mode == :paused && "badge-neutral",
        @mode == :hold && "badge-outline opacity-80"
      ]}
    >
      {transport_mode_label(@mode)}
    </span>
    """
  end

  defp transport_mode_label(:rotating), do: "Rotating"
  defp transport_mode_label(:takeover), do: "Takeover"
  defp transport_mode_label(:paused), do: "Paused"
  defp transport_mode_label(:hold), do: "Hold"
  defp transport_mode_label(_), do: ""

  attr :playing, :boolean, required: true
  attr :countdown_percent, :integer, required: true
  attr :countdown_label, :string, required: true

  def countdown_ring(assigns) do
    ~H"""
    <div
      class={[
        "radial-progress console-mono text-sm shrink-0",
        @playing && "text-[#00d390]",
        !@playing && "opacity-40"
      ]}
      style={"--value:#{@countdown_percent}; --size:3.25rem; --thickness:3px;"}
      role="timer"
    >
      {@countdown_label}
    </div>
    """
  end

  attr :interval_seconds, :integer, required: true
  attr :interval_custom?, :boolean, required: true
  attr :target, :any, default: nil

  def interval_picker(assigns) do
    ~H"""
    <div>
      <div class="text-[11px] uppercase tracking-wide opacity-60 mb-1">Change mode every</div>
      <div class="join">
        <button
          :for={{label, seconds} <- interval_presets()}
          class={[
            "btn btn-sm join-item min-h-11",
            @interval_seconds == seconds && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
          ]}
          phx-click="set_interval"
          phx-value-seconds={seconds}
          phx-target={@target}
        >
          {label}
        </button>
        <button
          class={[
            "btn btn-sm join-item min-h-11",
            @interval_custom? && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
          ]}
          phx-click="open_custom_interval"
          phx-target={@target}
        >
          …
        </button>
      </div>
    </div>
    """
  end

  attr :queue, :list, required: true
  attr :count, :integer, required: true
  attr :interval_label, :string, required: true
  attr :live_index, :integer, default: nil
  attr :up_next_index, :integer, default: nil
  attr :elapsed_percent, :integer, required: true
  attr :countdown_label, :string, required: true
  attr :holding_label, :string, required: true
  attr :target, :any, default: nil

  def queue_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-3">
        <div class="flex items-center justify-between">
          <h2 class="text-base font-semibold">Playlist</h2>
          <span class="text-xs opacity-60">
            <%= if @count == 0 do %>
              empty
            <% else %>
              {@count} {ngettext("mode", "modes", @count)} · every {@interval_label}
            <% end %>
          </span>
        </div>

        <div
          :if={@count == 0}
          class="border-2 border-dashed border-base-content/20 rounded-lg p-6 text-center text-sm opacity-70"
        >
          <div class="font-semibold mb-1">Nothing in playlist</div>
          The wall keeps showing {@holding_label}. Add modes with ＋ Playlist.
        </div>

        <div :if={@count > 0} class="flex flex-col gap-2">
          <.queue_row
            :for={{entry, idx} <- Enum.with_index(@queue)}
            entry={entry}
            idx={idx}
            count={@count}
            live?={@live_index == idx}
            up_next?={@up_next_index == idx}
            elapsed_percent={@elapsed_percent}
            countdown_label={@countdown_label}
            target={@target}
          />
        </div>

        <p :if={@count == 1} class="text-xs opacity-60">
          One mode holds steady — add another to start rotating.
        </p>
        <p :if={@count > 1} class="text-xs opacity-60">
          Reorder with the arrows — the wall follows this order, top to bottom, then repeats.
        </p>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :idx, :integer, required: true
  attr :count, :integer, required: true
  attr :live?, :boolean, required: true
  attr :up_next?, :boolean, required: true
  attr :elapsed_percent, :integer, required: true
  attr :countdown_label, :string, required: true
  attr :target, :any, default: nil

  def queue_row(assigns) do
    ~H"""
    <div class={[
      "relative flex items-center gap-2 rounded-lg border p-2 overflow-hidden",
      @live? && "border-[#00d390] bg-[#00d390]/10",
      !@live? && "border-base-300 bg-base-100"
    ]}>
      <span class="w-5 text-center text-xs opacity-60">{@idx + 1}</span>
      <span class="w-1 h-8 rounded shrink-0" style={"background-color: #{@entry.accent_color}"} />
      <div class="flex-1 min-w-0">
        <div class="text-[10px] uppercase tracking-wide opacity-60 truncate">{@entry.app_name}</div>
        <div class="font-semibold text-sm truncate">{@entry.mode_name}</div>
      </div>

      <.live_badge :if={@live?} />
      <span :if={@up_next? and not @live?} class="badge badge-outline badge-sm">
        up next · {@countdown_label}
      </span>

      <div class="flex items-center gap-1">
        <button
          class="btn btn-ghost btn-xs btn-square w-8 h-8"
          phx-click="queue_move"
          phx-value-index={@idx}
          phx-value-dir="up"
          phx-target={@target}
          disabled={@idx == 0}
        >
          ▲
        </button>
        <button
          class="btn btn-ghost btn-xs btn-square w-8 h-8"
          phx-click="queue_move"
          phx-value-index={@idx}
          phx-value-dir="down"
          phx-target={@target}
          disabled={@idx == @count - 1}
        >
          ▼
        </button>
        <button
          class="btn btn-ghost btn-xs btn-square w-8 h-8"
          phx-click="queue_remove"
          phx-value-index={@idx}
          phx-target={@target}
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

  attr :mode, :map, required: true
  attr :app_name, :string, required: true
  attr :app_module, :atom, required: true
  attr :live?, :boolean, default: false
  attr :queued_pos, :integer, default: nil
  attr :queueable?, :boolean, default: true
  attr :play_now_title, :string, default: "Show on the wall"
  attr :stop_takeover?, :boolean, default: false
  attr :target, :any, default: nil

  def mode_tile(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 overflow-hidden">
      <div class="h-1" style={"background-color: #{@mode.accent_color}"} />
      <div class="card-body p-3 gap-2">
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0">
            <div class="text-[10px] uppercase tracking-wide opacity-60">{@app_name}</div>
            <h3 class="font-semibold text-sm leading-tight truncate">{@mode.name}</h3>
          </div>
          <div class="flex items-center gap-1 shrink-0">
            <.live_badge :if={@live?} />
            <span :if={@queued_pos} class="badge badge-outline badge-sm">Nr. {@queued_pos}</span>
            <span :if={Map.get(@mode, :builtin) == false} class="badge badge-outline badge-sm opacity-70">
              yours
            </span>
          </div>
        </div>

        <p :if={@mode[:formula]} class="console-mono text-xs opacity-70 truncate" title={@mode.formula}>
          {@mode.formula}
        </p>
        <p :if={@mode[:summary] && @mode[:summary] != ""} class="text-xs opacity-70 truncate">
          {@mode.summary}
        </p>

        <div class="flex gap-2 mt-1">
          <button
            :if={@stop_takeover?}
            class="btn btn-sm btn-square btn-error min-h-11 min-w-11"
            phx-click="stop_takeover"
            phx-value-app={Atom.to_string(@app_module)}
            phx-value-mode_id={@mode.id}
            phx-target={@target}
            title="Stop"
          >
            ■
          </button>
          <button
            :if={!@stop_takeover?}
            class="btn btn-sm btn-square min-h-11 min-w-11"
            phx-click="play_now"
            phx-value-app={Atom.to_string(@app_module)}
            phx-value-mode_id={@mode.id}
            phx-target={@target}
            title={@play_now_title}
          >
            ▶
          </button>
          <button
            :if={@queueable?}
            class={[
              "btn btn-sm btn-square min-h-11 min-w-11",
              @queued_pos && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
            ]}
            phx-click="queue_toggle"
            phx-value-app={Atom.to_string(@app_module)}
            phx-value-mode_id={@mode.id}
            phx-target={@target}
            title={if @queued_pos, do: "In playlist", else: "Add to playlist"}
          >
            {if @queued_pos, do: "✓", else: "＋"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true

  def soon_tile(assigns) do
    ~H"""
    <div class="card border-2 border-dashed border-base-content/20 min-h-[7rem] flex items-center justify-center text-center p-3 text-sm opacity-50">
      {@label} — soon
    </div>
    """
  end

  attr :running_apps, :list, required: true
  attr :target, :any, default: nil

  def running_now_rows(assigns) do
    ~H"""
    <div class="space-y-0">
      <div :if={@running_apps == []} class="text-sm opacity-60 text-center py-4">
        No apps running.
      </div>

      <div :for={app <- @running_apps} class="flex flex-wrap items-center gap-2 py-2 border-b border-base-300 last:border-0">
        <span class={["w-2 h-2 rounded-full", app.selected && "bg-[#00d390]", !app.selected && "bg-base-content/30"]} />
        <span class="font-medium flex-1 min-w-[8rem]">{app.name}</span>
        <span :if={app.selected} class="badge badge-sm bg-[#00d390] text-black border-0">Active</span>
        <span :if={app.masked} class="badge badge-neutral badge-sm">Masked</span>
        <div class="flex gap-1 ml-auto">
          <button
            class={["btn btn-sm", app.selected && "btn-success", !app.selected && "btn-outline"]}
            phx-click="select_app"
            phx-value-app-id={app.app_id}
            phx-target={@target}
          >
            Show
          </button>
          <button
            class={["btn btn-sm", app.masked && "btn-neutral", !app.masked && "btn-outline"]}
            phx-click="mask_app"
            phx-value-app-id={app.app_id}
            phx-target={@target}
          >
            Mask
          </button>
          <button
            class="btn btn-sm btn-error"
            phx-click="stop_app"
            phx-value-app-id={app.app_id}
            phx-target={@target}
          >
            Stop
          </button>
        </div>
      </div>
    </div>
    """
  end

  def live_badge(assigns) do
    ~H"""
    <span class="badge badge-sm bg-[#00d390] text-black border-0 font-semibold">LIVE</span>
    """
  end

  attr :now_playing, :map, default: nil
  attr :live, :map, default: nil
  attr :transform_live, :map, default: nil
  attr :rotating?, :boolean, default: false
  attr :playing, :boolean, default: true
  attr :countdown_percent, :integer, default: 0
  attr :countdown_label, :string, default: "--:--"
  attr :id_suffix, :string, default: "main"
  attr :target, :any, required: true

  def now_playing_card(assigns) do
    visible_tweakables =
      if assigns.now_playing do
        visible_now_playing_tweakables(assigns.now_playing)
      else
        []
      end

    formula_spec = Enum.find(visible_tweakables, &(&1.type == :formula))
    control_tweakables = Enum.reject(visible_tweakables, &(&1.type == :formula))
    control_rows = group_now_playing_controls(control_tweakables, visible_tweakables)

    assigns =
      assign(assigns,
        visible_tweakables: visible_tweakables,
        formula_spec: formula_spec,
        control_tweakables: control_tweakables,
        control_rows: control_rows,
        has_tweakables: visible_tweakables != [],
        has_formula: formula_spec != nil,
        has_controls: control_rows != [],
        show_countdown: assigns.rotating?,
        formula_valid: now_playing_formula_valid?(assigns.now_playing),
        formula_error: now_playing_formula_error(assigns.now_playing)
      )

    ~H"""
    <div :if={@now_playing && @live} id={"now-playing-#{@id_suffix}"} class="card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-4 gap-3">
        <div class="flex items-center justify-between gap-3">
          <h2 class="text-base font-semibold">Now playing</h2>
          <.countdown_ring
            :if={@show_countdown}
            playing={@playing}
            countdown_percent={@countdown_percent}
            countdown_label={@countdown_label}
          />
        </div>

        <div class="flex items-start gap-3">
          <span
            class="w-1 self-stretch rounded-full shrink-0"
            style={"background:#{@live.accent_color}"}
          />
          <div class="flex-1 min-w-0">
            <div class="text-xs opacity-60">{@live.app_name}</div>
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-semibold">{@live.mode_name}</span>
              <span
                :if={@now_playing.dirty}
                class="badge badge-sm gap-1 border-[#fcb700] text-[#fcb700] bg-transparent"
              >
                <span class="w-2 h-2 rounded-full bg-[#fcb700]" /> Unsaved
              </span>
            </div>
          </div>
        </div>

        <form
          :if={@has_formula}
          id={"now-playing-formula-#{@id_suffix}"}
          phx-change="now_playing_change"
          phx-target={@target}
          class="space-y-1"
        >
          <label class="text-sm font-semibold" for={"now-playing-program-#{@id_suffix}"}>
            {@formula_spec.label}
          </label>
          <p :if={@formula_spec[:hint]} class="console-mono text-[11px] opacity-60">{@formula_spec.hint}</p>
          <input
            type="text"
            id={"now-playing-program-#{@id_suffix}"}
            name={Atom.to_string(@formula_spec.key)}
            value={now_playing_formula_value(@now_playing.effective, @formula_spec.key)}
            phx-debounce="150"
            class={[
              "input input-bordered w-full console-mono text-sm min-h-11",
              !@formula_valid && "border-[#ff6266] focus:border-[#ff6266]",
              now_playing_value_dirty?(@now_playing, @formula_spec.key) && @formula_valid &&
                "border-[#fcb700]"
            ]}
          />
          <p :if={@formula_valid} class="text-xs text-[#00d390]">
            ✓ Valid — updating the wall as you type
          </p>
          <p :if={!@formula_valid} class="text-xs text-[#ff6266]">
            ✕ Invalid formula — {@formula_error || "syntax error"}. The wall keeps the last valid formula.
          </p>
        </form>

        <form
          :if={@has_controls}
          id={"now-playing-tweaks-#{@id_suffix}"}
          phx-change="now_playing_change"
          phx-target={@target}
          class={["space-y-4", @has_formula && "mt-4"]}
        >
          <div
            :for={row <- @control_rows}
            id={"now-playing-row-#{row_dom_id(row)}-#{@id_suffix}"}
            class="space-y-1"
          >
            <%= case row do %>
              <% {:slider, spec, auto_spec, nested} -> %>
                <div class="space-y-2">
                  <div
                    id={"now-playing-slider-#{spec.key}-#{@id_suffix}"}
                    phx-hook=".NowPlayingSlider"
                    data-value={Map.get(@now_playing.effective, spec.key)}
                    data-step={spec.step}
                    data-min={spec.min}
                    data-max={spec.max}
                    data-unit={spec[:unit]}
                    class="space-y-1"
                  >
                    <label class="text-sm" for={"now-playing-#{spec.key}-#{@id_suffix}"}>{spec.label}</label>
                    <div class="flex items-center gap-2">
                      <input
                        type="range"
                        id={"now-playing-#{spec.key}-#{@id_suffix}"}
                        name={Atom.to_string(spec.key)}
                        min={spec.min}
                        max={spec.max}
                        step={spec.step}
                        value={now_playing_slider_value(@now_playing, spec)}
                        disabled={now_playing_disabled?(@now_playing, spec)}
                        phx-debounce="50"
                        class={[
                          "range range-primary range-sm min-w-0 flex-1",
                          now_playing_disabled?(@now_playing, spec) && "opacity-40"
                        ]}
                      />
                      <input
                        type="number"
                        data-number-input
                        min={spec.min}
                        max={spec.max}
                        step={spec.step}
                        value={now_playing_slider_display(@now_playing, spec)}
                        disabled={now_playing_disabled?(@now_playing, spec)}
                        phx-debounce="150"
                        class={[
                          "input input-bordered input-sm w-16 shrink-0 console-mono text-xs tabular-nums px-1 text-center",
                          now_playing_value_dirty?(@now_playing, spec.key) && "border-[#fcb700]",
                          now_playing_disabled?(@now_playing, spec) && "opacity-40"
                        ]}
                      />
                      <span :if={spec[:unit]} class="text-[11px] opacity-60 shrink-0 w-8">{spec[:unit]}</span>
                      <label
                        :if={auto_spec}
                        class="flex items-center gap-1.5 shrink-0 cursor-pointer select-none"
                        title={auto_spec.label}
                      >
                        <span class="text-[11px] opacity-70">{auto_spec.label}</span>
                        <input
                          type="hidden"
                          name={Atom.to_string(auto_spec.key)}
                          value="false"
                        />
                        <input
                          type="checkbox"
                          id={"now-playing-#{auto_spec.key}-#{@id_suffix}"}
                          name={Atom.to_string(auto_spec.key)}
                          value="true"
                          checked={Map.get(@now_playing.effective, auto_spec.key) == true}
                          class="toggle toggle-sm toggle-primary shrink-0 focus:outline-none focus:ring-0 focus:ring-offset-0"
                        />
                      </label>
                    </div>
                  </div>

                  <div
                    :if={nested != []}
                    class="ml-3 space-y-1.5 border-l border-base-300 pl-3"
                  >
                    <div
                      :for={sub <- nested}
                      id={"now-playing-slider-#{sub.key}-#{@id_suffix}"}
                      phx-hook=".NowPlayingSlider"
                      data-value={Map.get(@now_playing.effective, sub.key)}
                      data-step={sub.step}
                      data-min={sub.min}
                      data-max={sub.max}
                      data-unit={sub[:unit]}
                      class="space-y-0.5"
                    >
                      <label
                        class="text-[11px] opacity-70"
                        for={"now-playing-#{sub.key}-#{@id_suffix}"}
                      >
                        {sub.label}
                      </label>
                      <div class="flex items-center gap-1.5">
                        <input
                          type="range"
                          id={"now-playing-#{sub.key}-#{@id_suffix}"}
                          name={Atom.to_string(sub.key)}
                          min={sub.min}
                          max={sub.max}
                          step={sub.step}
                          value={Map.get(@now_playing.effective, sub.key)}
                          phx-debounce="50"
                          class="range range-primary range-nested min-w-0 flex-1"
                        />
                        <input
                          type="number"
                          data-number-input
                          min={sub.min}
                          max={sub.max}
                          step={sub.step}
                          value={format_tweak_number_raw(Map.get(@now_playing.effective, sub.key))}
                          phx-debounce="150"
                          class={[
                            "input input-bordered input-xs w-12 shrink-0 console-mono text-[11px] tabular-nums px-1 text-center h-7 min-h-0",
                            now_playing_value_dirty?(@now_playing, sub.key) && "border-[#fcb700]"
                          ]}
                        />
                        <span :if={sub[:unit]} class="text-[10px] opacity-60 shrink-0">{sub[:unit]}</span>
                      </div>
                    </div>
                  </div>
                </div>
              <% {:control, spec} -> %>
                <div class="space-y-1">
                  <label
                    :if={spec.type != :toggle}
                    class="text-sm"
                    for={"now-playing-#{spec.key}-#{@id_suffix}"}
                  >
                    {spec.label}
                  </label>
                  <div
                    :if={spec.type == :toggle}
                    class="flex items-center justify-between gap-2"
                  >
                    <label class="text-sm" for={"now-playing-#{spec.key}-#{@id_suffix}"}>
                      {spec.label}
                    </label>
                    <input
                      type="hidden"
                      name={Atom.to_string(spec.key)}
                      value="false"
                    />
                    <input
                      type="checkbox"
                      id={"now-playing-#{spec.key}-#{@id_suffix}"}
                      name={Atom.to_string(spec.key)}
                      value="true"
                      checked={Map.get(@now_playing.effective, spec.key) == true}
                      class="toggle toggle-sm toggle-primary shrink-0 focus:outline-none focus:ring-0 focus:ring-offset-0"
                    />
                  </div>
                  <%= cond do %>
                    <% spec.type == :toggle -> %>
                    <% spec.type == :choice -> %>
                      <div class="join flex-wrap">
                        <button
                          :for={{option, idx} <- Enum.with_index(spec.options)}
                          type="button"
                          class={[
                            "btn btn-sm join-item min-h-11",
                            Map.get(@now_playing.effective, spec.key) == elem(option, 0) && "btn-primary"
                          ]}
                          phx-click="now_playing_choice"
                          phx-value-key={spec.key}
                          phx-value-index={idx}
                          phx-target={@target}
                        >
                          {elem(option, 1)}
                        </button>
                      </div>
                    <% spec.type == :color -> %>
                      <input
                        type="color"
                        id={"now-playing-#{spec.key}-#{@id_suffix}"}
                        name={Atom.to_string(spec.key)}
                        value={Map.get(@now_playing.effective, spec.key, spec[:default] || "#ffffff")}
                        phx-debounce="50"
                        class="w-full h-11 min-h-11 cursor-pointer rounded-lg border border-base-300 bg-base-100"
                      />
                    <% true -> %>
                  <% end %>
                </div>
            <% end %>
          </div>
        </form>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".NowPlayingSlider">
          function formatRaw(value, step) {
            const num = Number(value)
            if (!Number.isFinite(num)) return ""
            const stepNum = Number(step)
            if (Number.isInteger(stepNum) && stepNum >= 1) return String(Math.round(num))
            // Match server tabular display for typical float steps
            if (Math.abs(stepNum) >= 0.1) return num.toFixed(1)
            return String(Math.round(num * 100) / 100)
          }

          function clamp(num, min, max) {
            return Math.min(Math.max(num, min), max)
          }

          export default {
            mounted() {
              this.bindElements()
              this.onRangeInput = () => {
                if (this.number) {
                  this.number.value = formatRaw(this.range.value, this.el.dataset.step)
                }
              }
              this.onNumberChange = () => {
                if (!this.range || !this.number) return
                let num = Number(this.number.value)
                if (!Number.isFinite(num)) {
                  this.number.value = formatRaw(this.range.value, this.el.dataset.step)
                  return
                }
                num = clamp(num, Number(this.el.dataset.min), Number(this.el.dataset.max))
                this.range.value = String(num)
                this.number.value = formatRaw(num, this.el.dataset.step)
                this.range.dispatchEvent(new Event("input", { bubbles: true }))
                this.range.dispatchEvent(new Event("change", { bubbles: true }))
              }
              this.range.addEventListener("input", this.onRangeInput)
              this.number.addEventListener("change", this.onNumberChange)
            },
            updated() {
              this.bindElements()
              if (!this.range) return
              if (document.activeElement === this.range || document.activeElement === this.number) return
              this.range.value = this.el.dataset.value
              if (this.number) {
                this.number.value = formatRaw(this.range.value, this.el.dataset.step)
              }
            },
            destroyed() {
              if (this.range && this.onRangeInput) {
                this.range.removeEventListener("input", this.onRangeInput)
              }
              if (this.number && this.onNumberChange) {
                this.number.removeEventListener("change", this.onNumberChange)
              }
            },
            bindElements() {
              this.range = this.el.querySelector('input[type="range"]')
              this.number = this.el.querySelector("[data-number-input]")
            }
          }
        </script>

        <div
          :if={@now_playing.meta != []}
          class="rounded-lg bg-base-300/40 p-3 console-mono text-xs space-y-0.5"
        >
          <div :for={line <- @now_playing.meta}>{line}</div>
        </div>

        <div :if={@has_tweakables} class="flex flex-wrap gap-2 pt-3 border-t border-base-300">
          <button
            :if={@now_playing.persistable}
            type="button"
            class="btn btn-primary btn-sm min-h-11 bg-[#6d7cff] border-[#6d7cff]"
            phx-click="open_now_playing_save_modal"
            phx-target={@target}
            disabled={!@formula_valid}
          >
            Save as new…
          </button>
          <button
            :if={@now_playing.persistable && @now_playing.overwriteable}
            type="button"
            class="btn btn-sm min-h-11"
            phx-click="now_playing_overwrite"
            phx-target={@target}
            disabled={!@now_playing.dirty or !@formula_valid}
          >
            Overwrite
          </button>
          <button
            :if={@now_playing.renamable}
            type="button"
            class="btn btn-sm min-h-11"
            phx-click="open_now_playing_rename_modal"
            phx-target={@target}
          >
            Rename…
          </button>
          <button
            :if={@now_playing.deletable}
            type="button"
            class="btn btn-sm min-h-11 text-error"
            phx-click="open_now_playing_delete_modal"
            phx-target={@target}
          >
            Delete…
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-sm min-h-11"
            phx-click="now_playing_discard"
            phx-target={@target}
            disabled={!@now_playing.dirty}
          >
            Discard
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-sm min-h-11 ml-auto link link-primary"
            phx-click="now_playing_full_editor"
            phx-target={@target}
          >
            Full editor →
          </button>
        </div>

        <p :if={@has_tweakables} class="text-xs opacity-60">
          Changes apply immediately. If the queue moves on, unsaved values are dropped.
        </p>
      </div>
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :target, :any, required: true
  attr :name, :string, default: ""
  attr :preset_label, :string, default: "preset"

  def now_playing_save_modal(assigns) do
    label = String.capitalize(assigns.preset_label)
    assigns = assign(assigns, :label, label)

    ~H"""
    <div :if={@show} class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Save as new {@label}</h3>
        <form
          phx-change="now_playing_save_name_change"
          phx-submit="now_playing_save_as_new"
          phx-target={@target}
          class="space-y-4 mt-2"
        >
          <input
            type="text"
            name="name"
            value={@name}
            placeholder={"#{@label} name"}
            class="input input-bordered w-full"
            autofocus
          />
          <div class="modal-action mt-0">
            <button type="button" class="btn btn-ghost" phx-click="close_now_playing_save_modal" phx-target={@target}>
              Cancel
            </button>
            <button type="submit" class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]">Save</button>
          </div>
        </form>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_now_playing_save_modal" phx-target={@target} />
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :target, :any, required: true
  attr :name, :string, default: ""
  attr :preset_label, :string, default: "preset"

  def now_playing_rename_modal(assigns) do
    label = String.capitalize(assigns.preset_label)
    assigns = assign(assigns, :label, label)

    ~H"""
    <div :if={@show} class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Rename {@label}</h3>
        <form
          phx-change="now_playing_rename_change"
          phx-submit="now_playing_rename"
          phx-target={@target}
          class="space-y-4 mt-2"
        >
          <input
            type="text"
            name="name"
            value={@name}
            placeholder={"#{@label} name"}
            class="input input-bordered w-full"
            autofocus
          />
          <div class="modal-action mt-0">
            <button type="button" class="btn btn-ghost" phx-click="close_now_playing_rename_modal" phx-target={@target}>
              Cancel
            </button>
            <button type="submit" class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]">Rename</button>
          </div>
        </form>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_now_playing_rename_modal" phx-target={@target} />
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :target, :any, required: true
  attr :preset_name, :string, default: ""
  attr :preset_label, :string, default: "preset"

  def now_playing_delete_modal(assigns) do
    label = String.capitalize(assigns.preset_label)
    assigns = assign(assigns, :label, label)

    ~H"""
    <div :if={@show} class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Delete {@label}?</h3>
        <p class="py-2">
          Remove <span class="font-semibold">{@preset_name}</span> from the library. The playlist will be updated.
        </p>
        <div class="modal-action">
          <button type="button" class="btn btn-ghost" phx-click="close_now_playing_delete_modal" phx-target={@target}>
            Cancel
          </button>
          <button type="button" class="btn text-[#ff6266]" phx-click="now_playing_delete" phx-target={@target}>
            Delete
          </button>
        </div>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_now_playing_delete_modal" phx-target={@target} />
    </div>
    """
  end

  defp now_playing_value_dirty?(now_playing, key) do
    Map.has_key?(now_playing.overrides, key)
  end

  defp visible_now_playing_tweakables(now_playing) do
    Enum.filter(now_playing.tweakables, &now_playing_tweakable_visible?(&1, now_playing.effective))
  end

  defp group_now_playing_controls(control_tweakables, all_visible) do
    by_key = Map.new(all_visible, &{&1.key, &1})

    companion_keys =
      control_tweakables
      |> Enum.filter(&Map.has_key?(&1, :auto_key))
      |> MapSet.new(& &1.auto_key)

    nested_by_auto =
      control_tweakables
      |> Enum.filter(&nested_auto_subcontrol?/1)
      |> Enum.group_by(fn %{visible_when: {auto_key, _}} -> auto_key end)

    nested_keys =
      nested_by_auto
      |> Map.values()
      |> List.flatten()
      |> MapSet.new(& &1.key)

    control_tweakables
    |> Enum.reject(&(&1.key in companion_keys or &1.key in nested_keys))
    |> Enum.map(fn
      %{type: :slider} = spec ->
        auto_spec =
          case spec[:auto_key] do
            nil -> nil
            key -> Map.get(by_key, key)
          end

        nested =
          case spec[:auto_key] do
            nil -> []
            key -> Map.get(nested_by_auto, key, [])
          end

        {:slider, spec, auto_spec, nested}

      spec ->
        {:control, spec}
    end)
  end

  defp nested_auto_subcontrol?(%{type: :slider, visible_when: {dep, _}}) when is_atom(dep) do
    dep |> Atom.to_string() |> String.ends_with?("_auto")
  end

  defp nested_auto_subcontrol?(_), do: false

  defp row_dom_id({:slider, spec, _, _}), do: spec.key
  defp row_dom_id({:control, spec}), do: spec.key

  defp now_playing_tweakable_visible?(%{visible_when: {dep_key, allowed}}, effective) do
    Map.get(effective, dep_key) in allowed
  end

  defp now_playing_tweakable_visible?(_, _), do: true

  defp now_playing_disabled?(%{effective: effective}, %{disabled_when: {dep_key, allowed}}) do
    Map.get(effective, dep_key) in allowed
  end

  defp now_playing_disabled?(_, _), do: false

  defp now_playing_slider_value(now_playing, spec) do
    live = Map.get(now_playing, :transform_live) || %{}

    cond do
      now_playing_disabled?(now_playing, spec) and spec.key == :zoom_base and
          is_number(Map.get(live, :zoom_factor)) ->
        Map.get(live, :zoom_factor)

      now_playing_disabled?(now_playing, spec) and is_number(Map.get(live, spec.key)) ->
        Map.get(live, spec.key)

      true ->
        Map.get(now_playing.effective, spec.key)
    end
  end

  defp now_playing_slider_display(now_playing, spec) do
    value = now_playing_slider_value(now_playing, spec)

    cond do
      spec.key == :zoom_base and is_number(value) ->
        "×" <> format_tweak_number_raw(Float.round(value * 1.0, 1))

      now_playing_disabled?(now_playing, spec) and is_number(value) ->
        format_tweak_number_raw(Float.round(value * 1.0, 1))

      true ->
        format_tweak_number_raw(value)
    end
  end

  defp format_tweak_number_raw(value) when is_integer(value), do: Integer.to_string(value)

  defp format_tweak_number_raw(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2) |> String.trim_trailing("0") |> String.trim_trailing(".")
  end

  defp format_tweak_number_raw(value) when is_binary(value), do: value
  defp format_tweak_number_raw(value), do: to_string(value)

  defp now_playing_formula_valid?(nil), do: true

  defp now_playing_formula_valid?(%{tweakables: tweakables, effective: effective}) do
    case Enum.find(tweakables, &(&1.type == :formula)) do
      nil -> true
      %{key: key} -> ScenePresets.validate_formula(now_playing_formula_value(effective, key)) == :ok
    end
  end

  defp now_playing_formula_valid?(_), do: true

  defp now_playing_formula_error(nil), do: nil

  defp now_playing_formula_error(%{tweakables: tweakables, effective: effective}) do
    case Enum.find(tweakables, &(&1.type == :formula)) do
      nil ->
        nil

      %{key: key} ->
        formula_error_token(now_playing_formula_value(effective, key))
    end
  end

  defp now_playing_formula_error(_), do: nil

  defp now_playing_formula_value(effective, key) when is_map(effective) do
    effective
    |> Map.get(key)
    |> case do
      value when is_binary(value) -> value
      nil -> ""
      value -> to_string(value)
    end
  end

  defp formula_error_token(formula) when is_binary(formula) do
    case ScenePresets.validate_formula(formula) do
      :ok ->
        nil

      :error ->
        Regex.scan(~r/[A-Za-z_][A-Za-z0-9_]*/, formula)
        |> List.flatten()
        |> Enum.find(&(&1 not in @known_formula_idents))
        |> Kernel.||("?")
    end
  end

  defp formula_error_token(_), do: "?"

  attr :show, :boolean, required: true
  attr :target, :any, default: nil

  def custom_interval_modal(assigns) do
    ~H"""
    <div :if={@show} class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Custom interval</h3>
        <form phx-submit="save_custom_interval" phx-target={@target} class="space-y-4 mt-2">
          <div class="flex gap-2">
            <input type="number" name="value" min="1" step="1" value="1" class="input input-bordered flex-1" />
            <select name="unit" class="select select-bordered">
              <option value="s">seconds</option>
              <option value="min" selected>minutes</option>
              <option value="h">hours</option>
            </select>
          </div>
          <div class="modal-action mt-0">
            <button type="button" class="btn btn-ghost" phx-click="close_custom_interval" phx-target={@target}>
              Cancel
            </button>
            <button type="submit" class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]">Set</button>
          </div>
        </form>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_custom_interval" phx-target={@target} />
    </div>
    """
  end

  def format_mmss(nil), do: "--:--"

  def format_mmss(ms) when is_integer(ms) do
    total = div(ms, 1000)
    minutes = div(total, 60)
    seconds = rem(total, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  def interval_label(seconds) do
    case Enum.find(interval_presets(), fn {_l, s} -> s == seconds end) do
      {label, _} -> label
      nil -> humanize_interval(seconds)
    end
  end

  def humanize_interval(seconds) do
    cond do
      rem(seconds, 3600) == 0 -> "#{div(seconds, 3600)} h"
      rem(seconds, 60) == 0 -> "#{div(seconds, 60)} min"
      true -> "#{seconds} s"
    end
  end

  def queue_position([%{app: app, mode_id: mid} | _], app, mode_id, pos) when mid == mode_id, do: pos

  def queue_position([_ | rest], app, mode_id, pos),
    do: queue_position(rest, app, mode_id, pos + 1)

  def queue_position([], _app, _mode_id, _pos), do: nil

  def entry_key(%{app: app, mode_id: mode_id}), do: {app, mode_id}

  def live?(transport, app, mode_id) do
    case transport.live do
      %{app: live_app, mode_id: live_mode} when live_app == app and live_mode == mode_id -> true
      _ -> false
    end
  end

  def takeover_live?(transport, app, mode_id) do
    transport.rotation_paused &&
      live?(transport, app, mode_id) &&
      is_nil(queue_position(transport.queue, app, mode_id, 1))
  end
end
