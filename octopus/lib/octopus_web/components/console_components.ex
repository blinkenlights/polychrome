defmodule OctopusWeb.ConsoleComponents do
  @moduledoc false
  use OctopusWeb, :html

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
  attr :live_label, :string, required: true
  attr :live?, :boolean, default: false
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
          <.transport_controls rotating?={@rotating?} target={@target} playing={@playing} />

          <div class="flex-1 min-w-[12rem]">
            <div class="text-[11px] uppercase tracking-wide opacity-60">Now on the wall</div>
            <div class="flex items-center gap-2">
              <span class="text-lg font-semibold">{@live_label}</span>
              <.live_badge :if={@live?} />
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
  attr :live_label, :string, required: true
  attr :live?, :boolean, default: false
  attr :subtitle, :string, required: true
  attr :countdown_percent, :integer, required: true
  attr :countdown_label, :string, required: true
  attr :target, :any, default: nil

  def mini_transport(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-3 flex-row items-center gap-3">
        <button
          class="btn btn-circle btn-primary btn-sm w-11 h-11"
          phx-click="toggle_play"
          phx-target={@target}
          aria-label={if @playing, do: "Pause", else: "Play"}
        >
          {if @playing, do: "❚❚", else: "▶"}
        </button>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-semibold truncate">{@live_label}</span>
            <.live_badge :if={@live?} />
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
        class="btn btn-circle btn-primary bg-[#6d7cff] border-[#6d7cff] hover:bg-[#5b6aff] w-14 h-14 text-lg"
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
          <h2 class="text-base font-semibold">Queue</h2>
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
          <div class="font-semibold mb-1">Nothing queued</div>
          The wall keeps showing {@holding_label}. Add modes with ＋ Queue.
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
            class={["btn btn-sm min-h-11", @queueable? && "flex-1"]}
            phx-click="play_now"
            phx-value-app={@app_module}
            phx-value-mode_id={@mode.id}
            phx-target={@target}
          >
            ▶ Play now
          </button>
          <button
            :if={@queueable?}
            class={[
              "btn btn-sm flex-1 min-h-11",
              @queued_pos && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
            ]}
            phx-click="queue_toggle"
            phx-value-app={@app_module}
            phx-value-mode_id={@mode.id}
            phx-target={@target}
          >
            {if @queued_pos, do: "✓ Queued", else: "＋ Queue"}
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

  def running_now_strip(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-3">
        <div class="flex items-center justify-between">
          <h2 class="text-base font-semibold">Running now</h2>
          <span class="text-xs opacity-60">Only one app is Active at a time.</span>
        </div>

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
  attr :rotating?, :boolean, default: false
  attr :playing, :boolean, default: true
  attr :countdown_percent, :integer, default: 0
  attr :countdown_label, :string, default: "--:--"
  attr :target, :any, required: true

  def now_playing_card(assigns) do
    visible_tweakables =
      if assigns.now_playing do
        visible_now_playing_tweakables(assigns.now_playing)
      else
        []
      end

    assigns =
      assign(assigns,
        visible_tweakables: visible_tweakables,
        has_tweakables: visible_tweakables != [],
        show_countdown: assigns.rotating?
      )

    ~H"""
    <div :if={@now_playing && @live} id="now-playing" class="card bg-base-200 border border-base-300 shadow-sm">
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
              <.live_badge />
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
          :if={@has_tweakables}
          id="now-playing-tweaks"
          phx-change="now_playing_change"
          phx-target={@target}
          class="space-y-4"
        >
          <div :for={spec <- @visible_tweakables} class="space-y-1">
            <%= if spec.type == :slider do %>
              <div
                id={"now-playing-slider-#{spec.key}"}
                phx-hook=".NowPlayingSlider"
                data-value={Map.get(@now_playing.effective, spec.key)}
                data-unit={spec[:unit]}
                class="space-y-1"
              >
                <div class="flex items-baseline justify-between gap-2">
                  <label class="text-sm" for={"now-playing-#{spec.key}"}>{spec.label}</label>
                  <span
                    data-value-display
                    class={[
                      "console-mono text-xs tabular-nums",
                      now_playing_value_dirty?(@now_playing, spec.key) && "text-[#fcb700]",
                      !now_playing_value_dirty?(@now_playing, spec.key) && "opacity-70"
                    ]}
                  >
                    {format_tweakable_value(spec, Map.get(@now_playing.effective, spec.key))}
                  </span>
                </div>
                <input
                  type="range"
                  id={"now-playing-#{spec.key}"}
                  name={Atom.to_string(spec.key)}
                  min={spec.min}
                  max={spec.max}
                  step={spec.step}
                  value={Map.get(@now_playing.effective, spec.key)}
                  phx-debounce="50"
                  class="range range-primary range-sm w-full min-h-11"
                />
              </div>
            <% else %>
              <div class="flex items-baseline justify-between gap-2">
                <label class="text-sm" for={"now-playing-#{spec.key}"}>{spec.label}</label>
                <span class={[
                  "console-mono text-xs tabular-nums",
                  now_playing_value_dirty?(@now_playing, spec.key) && "text-[#fcb700]",
                  !now_playing_value_dirty?(@now_playing, spec.key) && "opacity-70"
                ]}>
                  {format_tweakable_value(spec, Map.get(@now_playing.effective, spec.key))}
                </span>
              </div>
              <%= cond do %>
                <% spec.type == :toggle -> %>
                  <input
                    type="hidden"
                    name={Atom.to_string(spec.key)}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id={"now-playing-#{spec.key}"}
                    name={Atom.to_string(spec.key)}
                    value="true"
                    checked={Map.get(@now_playing.effective, spec.key) == true}
                    class="toggle toggle-primary"
                  />
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
                    id={"now-playing-#{spec.key}"}
                    name={Atom.to_string(spec.key)}
                    value={Map.get(@now_playing.effective, spec.key, spec[:default] || "#ffffff")}
                    phx-debounce="50"
                    class="w-full h-11 min-h-11 cursor-pointer rounded-lg border border-base-300 bg-base-100"
                  />
                <% true -> %>
              <% end %>
            <% end %>
          </div>
        </form>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".NowPlayingSlider">
          function formatValue(value, unit) {
            const num = Number(value)
            const formatted = Number.isInteger(num) ? String(num) : num.toFixed(1)
            return unit ? `${formatted} ${unit}` : formatted
          }

          export default {
            mounted() {
              this.input = this.el.querySelector('input[type="range"]')
              this.display = this.el.querySelector("[data-value-display]")
              this.onInput = () => {
                this.display.textContent = formatValue(this.input.value, this.el.dataset.unit)
              }
              this.input.addEventListener("input", this.onInput)
            },
            updated() {
              if (document.activeElement !== this.input) {
                this.input.value = this.el.dataset.value
                this.display.textContent = formatValue(this.input.value, this.el.dataset.unit)
              }
            },
            destroyed() {
              this.input.removeEventListener("input", this.onInput)
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
          >
            Save as new…
          </button>
          <button
            :if={@now_playing.persistable && @now_playing.overwriteable}
            type="button"
            class="btn btn-sm min-h-11"
            phx-click="now_playing_overwrite"
            phx-target={@target}
            disabled={!@now_playing.dirty}
          >
            Overwrite
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

  def now_playing_save_modal(assigns) do
    ~H"""
    <div :if={@show} class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Save as new scene</h3>
        <form phx-submit="now_playing_save_as_new" phx-target={@target} class="space-y-4 mt-2">
          <input
            type="text"
            name="name"
            value={@name}
            placeholder="Scene name"
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

  defp now_playing_value_dirty?(now_playing, key) do
    Map.has_key?(now_playing.overrides, key)
  end

  defp visible_now_playing_tweakables(now_playing) do
    Enum.filter(now_playing.tweakables, &now_playing_tweakable_visible?(&1, now_playing.effective))
  end

  defp now_playing_tweakable_visible?(%{visible_when: {dep_key, allowed}}, effective) do
    Map.get(effective, dep_key) in allowed
  end

  defp now_playing_tweakable_visible?(_, _), do: true

  defp format_tweakable_value(%{type: :slider, unit: unit}, value) when is_binary(unit),
    do: "#{format_tweak_number(value)} #{unit}"

  defp format_tweakable_value(%{type: :slider}, value), do: format_tweak_number(value)
  defp format_tweakable_value(%{type: :choice, options: options}, value) do
    case Enum.find(options, fn {k, _} -> k == value end) do
      {_, label} -> label
      _ -> to_string(value)
    end
  end

  defp format_tweakable_value(%{type: :toggle}, true), do: "On"
  defp format_tweakable_value(%{type: :toggle}, _), do: "Off"
  defp format_tweakable_value(%{type: :color}, value) when is_binary(value), do: String.downcase(value)
  defp format_tweakable_value(_, value), do: to_string(value)

  defp format_tweak_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_tweak_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_tweak_number(n), do: to_string(n)

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
end
