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
            class="btn btn-sm flex-1 min-h-11"
            phx-click="play_now"
            phx-value-app={@app_module}
            phx-value-mode_id={@mode.id}
            phx-target={@target}
          >
            ▶ Play now
          </button>
          <button
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
