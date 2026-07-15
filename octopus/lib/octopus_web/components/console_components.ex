defmodule OctopusWeb.ConsoleComponents do
  @moduledoc false
  use OctopusWeb, :html

  alias Octopus.Apps.PixelFun.Program

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

  @transition_presets [
    {"Off", 0},
    {"0.5 s", 0.5},
    {"1 s", 1},
    {"2 s", 2}
  ]

  def interval_presets, do: @interval_presets
  def transition_presets, do: @transition_presets

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
  attr :interval_label, :string, required: true
  attr :transition_seconds, :float, required: true
  attr :transition_custom?, :boolean, required: true
  attr :transition_label, :string, default: ""
  attr :show_settings, :boolean, default: false
  attr :show_now_playing, :boolean, default: false
  attr :now_playing_available, :boolean, default: false
  attr :now_playing_dirty, :boolean, default: false
  attr :target, :any, default: nil

  def transport_bar(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-4">
        <.transport_status_row {assigns} />
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
  attr :interval_seconds, :integer, required: true
  attr :interval_custom?, :boolean, required: true
  attr :interval_label, :string, required: true
  attr :transition_seconds, :float, required: true
  attr :transition_custom?, :boolean, required: true
  attr :transition_label, :string, default: ""
  attr :show_settings, :boolean, default: false
  attr :show_now_playing, :boolean, default: false
  attr :now_playing_available, :boolean, default: false
  attr :now_playing_dirty, :boolean, default: false
  attr :queue, :list, required: true
  attr :count, :integer, required: true
  attr :live_index, :integer, default: nil
  attr :up_next_index, :integer, default: nil
  attr :elapsed_percent, :integer, required: true
  attr :holding_label, :string, required: true
  attr :front_app, :map, default: nil
  attr :mask_app, :map, default: nil
  attr :target, :any, default: nil

  slot :global_params, required: true

  def player_block(assigns) do
    ~H"""
    <div id="installation-player" class="card bg-base-200 border border-base-300 shadow-sm">
      <div class="sticky top-0 z-20 bg-base-200 border-b border-base-300 shadow-sm">
        <div class="p-3 min-[700px]:p-4 space-y-3">
          <.transport_status_row {assigns} />
          <div class="border-t border-base-300/60 pt-3">
            {render_slot(@global_params)}
          </div>
          <.slot_status_row
            :if={@front_app || @mask_app}
            front_app={@front_app}
            mask_app={@mask_app}
            target={@target}
          />
        </div>
      </div>
      <div class="px-3 pb-2 pt-1 min-[700px]:px-4 min-[700px]:pb-3">
        <.queue_card
          queue={@queue}
          count={@count}
          interval_label={@interval_label}
          transition_label={@transition_label}
          live_index={@live_index}
          up_next_index={@up_next_index}
          elapsed_percent={@elapsed_percent}
          countdown_label={@countdown_label}
          holding_label={@holding_label}
          target={@target}
          embedded
        />
      </div>
    </div>
    """
  end

  attr :front_app, :map, default: nil
  attr :mask_app, :map, default: nil
  attr :target, :any, default: nil

  defp slot_status_row(assigns) do
    ~H"""
    <div class="border-t border-base-300/60 pt-3 flex flex-wrap items-center gap-x-4 gap-y-2">
      <div class="flex items-center gap-2 min-w-0">
        <span class="text-[10px] uppercase tracking-wider font-semibold opacity-50 shrink-0">Front</span>
        <%= if @front_app do %>
          <span class="w-1.5 h-1.5 rounded-full bg-[#00d390] shrink-0" />
          <span class="text-sm font-medium truncate max-w-[12rem]">{@front_app.name}</span>
          <button
            class="btn btn-xs btn-error btn-square min-h-7 min-w-7 shrink-0"
            phx-click="stop_front_app"
            phx-target={@target}
            title="Front-App beenden"
            aria-label="Front-App beenden"
          >
            <.console_icon_stop class="w-3 h-3" />
          </button>
        <% else %>
          <span class="text-sm opacity-40 italic">Leer</span>
        <% end %>
      </div>
      <div class="flex items-center gap-2 min-w-0">
        <span class="text-[10px] uppercase tracking-wider font-semibold opacity-50 shrink-0">Mask</span>
        <%= if @mask_app do %>
          <span class="w-1.5 h-1.5 rounded-full bg-base-content/50 shrink-0" />
          <span class="text-sm font-medium truncate max-w-[12rem]">{@mask_app.name}</span>
          <button
            class="btn btn-xs btn-error btn-square min-h-7 min-w-7 shrink-0"
            phx-click="stop_mask_app"
            phx-target={@target}
            title="Mask-App beenden"
            aria-label="Mask-App beenden"
          >
            <.console_icon_stop class="w-3 h-3" />
          </button>
        <% else %>
          <span class="text-sm opacity-40 italic">Keine Mask</span>
        <% end %>
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
  attr :interval_seconds, :integer, default: 300
  attr :interval_custom?, :boolean, default: false
  attr :interval_label, :string, default: "5 min"
  attr :transition_seconds, :float, default: 1.0
  attr :transition_custom?, :boolean, default: false
  attr :transition_label, :string, default: ""
  attr :show_settings, :boolean, default: false
  attr :show_now_playing, :boolean, default: false
  attr :now_playing_available, :boolean, default: false
  attr :now_playing_dirty, :boolean, default: false
  attr :target, :any, default: nil

  defp transport_status_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 min-[700px]:gap-4 flex-wrap">
      <div class="max-[699px]:hidden">
        <.transport_controls rotating?={@rotating?} takeover?={@takeover?} target={@target} playing={@playing} />
      </div>
      <div class="min-[700px]:hidden">
        <.transport_controls
          rotating?={@rotating?}
          takeover?={@takeover?}
          target={@target}
          playing={@playing}
          compact
        />
      </div>
      <div class="flex-1 min-w-[8rem]">
        <div class="text-[11px] uppercase tracking-wide opacity-60 max-[699px]:hidden">Now on the wall</div>
        <div class="flex items-center gap-2 flex-wrap">
          <span class="text-base min-[700px]:text-lg font-semibold truncate">{@live_label}</span>
          <.transport_mode_badge mode={@transport_mode} />
        </div>
        <div class="text-xs min-[700px]:text-sm opacity-70 truncate">{@subtitle}</div>
      </div>
      <div class="max-[699px]:hidden">
        <.transport_panel_buttons {assigns} />
      </div>
      <div class="min-[700px]:hidden">
        <.transport_panel_buttons {assigns} compact />
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
  attr :interval_seconds, :integer, default: 300
  attr :interval_custom?, :boolean, default: false
  attr :interval_label, :string, default: "5 min"
  attr :transition_seconds, :float, default: 1.0
  attr :transition_custom?, :boolean, default: false
  attr :transition_label, :string, default: ""
  attr :show_settings, :boolean, default: false
  attr :show_now_playing, :boolean, default: false
  attr :now_playing_available, :boolean, default: false
  attr :now_playing_dirty, :boolean, default: false
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
        <.transport_panel_buttons {assigns} compact />
      </div>
    </div>
    """
  end

  attr :playing, :boolean, required: true
  attr :rotating?, :boolean, required: true
  attr :countdown_percent, :integer, required: true
  attr :countdown_label, :string, required: true
  attr :interval_seconds, :integer, default: 300
  attr :interval_custom?, :boolean, default: false
  attr :interval_label, :string, default: "5 min"
  attr :transition_seconds, :float, default: 1.0
  attr :transition_custom?, :boolean, default: false
  attr :transition_label, :string, default: ""
  attr :show_settings, :boolean, default: false
  attr :show_now_playing, :boolean, default: false
  attr :now_playing_available, :boolean, default: false
  attr :now_playing_dirty, :boolean, default: false
  attr :compact, :boolean, default: false
  attr :target, :any, default: nil

  def transport_panel_buttons(assigns) do
    ~H"""
    <div class={["flex items-center gap-3 shrink-0", !@compact && "ml-auto sm:ml-0"]}>
      <button
        :if={@now_playing_available}
        type="button"
        class={[
          "btn btn-sm btn-square min-h-10 min-w-10 btn-ghost relative",
          @show_now_playing && "btn-active",
          @now_playing_dirty && !@show_now_playing && "border-[#fcb700] text-[#fcb700]"
        ]}
        phx-click="toggle_now_playing_panel"
        phx-target={@target}
        title="Now playing controls"
        aria-label="Now playing controls"
        aria-expanded={to_string(@show_now_playing)}
      >
        <.console_icon_cog class="w-5 h-5" />
        <span
          :if={@now_playing_dirty && !@show_now_playing}
          class="absolute top-1 right-1 w-2 h-2 rounded-full bg-[#fcb700]"
        />
      </button>

      <div class="relative">
        <button
          type="button"
          class={[
            "btn btn-sm btn-square min-h-10 min-w-10 btn-ghost",
            @show_settings && "btn-active"
          ]}
          phx-click="toggle_transport_settings"
          phx-target={@target}
          title={"Timing: #{transport_timing_summary(@interval_label, @transition_label)}"}
          aria-label="Rotation timing"
          aria-expanded={to_string(@show_settings)}
        >
          <.console_icon_dots_vertical class="w-5 h-5" />
        </button>
        <div
          :if={@show_settings}
          class="absolute right-0 top-full z-20 mt-3 w-[min(calc(100vw-3rem),38rem)] card bg-base-100 border border-base-300 shadow-lg"
        >
          <div class="card-body p-5 grid gap-6 sm:grid-cols-2 sm:gap-x-8">
            <div class="space-y-2">
              <.interval_picker
                interval_seconds={@interval_seconds}
                interval_custom?={@interval_custom?}
                target={@target}
              />
              <p class="text-xs opacity-60">
                Applies at the next change — the running countdown isn't reset.
              </p>
            </div>
            <div class="space-y-2">
              <.transition_picker
                transition_seconds={@transition_seconds}
                transition_custom?={@transition_custom?}
                target={@target}
              />
              <p class="text-xs opacity-60">
                Fade applies on the next switch — total duration, split out/in.
              </p>
            </div>
          </div>
        </div>
      </div>

      <.countdown_ring
        :if={@rotating?}
        playing={@playing}
        countdown_percent={@countdown_percent}
        countdown_label={@countdown_label}
      />
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
        <.console_icon_stop class="w-5 h-5" />
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
        <.console_icon_pause :if={@playing} class="w-6 h-6" />
        <.console_icon_play :if={!@playing} class="w-6 h-6" />
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
      <div class="text-[11px] uppercase tracking-wide opacity-60 mb-2">Change mode every</div>
      <div class="flex flex-wrap gap-2">
        <button
          :for={{label, seconds} <- interval_presets()}
          class={[
            "btn btn-sm min-h-10",
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
            "btn btn-sm min-h-10",
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

  attr :transition_seconds, :float, required: true
  attr :transition_custom?, :boolean, required: true
  attr :target, :any, default: nil

  def transition_picker(assigns) do
    ~H"""
    <div>
      <div class="text-[11px] uppercase tracking-wide opacity-60 mb-2">Fade through black</div>
      <div class="flex flex-wrap gap-2">
        <button
          :for={{label, seconds} <- transition_presets()}
          class={[
            "btn btn-sm min-h-10",
            @transition_seconds == seconds && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
          ]}
          phx-click="set_transition_duration"
          phx-value-seconds={seconds}
          phx-target={@target}
        >
          {label}
        </button>
        <button
          class={[
            "btn btn-sm min-h-10",
            @transition_custom? && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
          ]}
          phx-click="open_custom_transition"
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
  attr :transition_label, :string, default: ""
  attr :live_index, :integer, default: nil
  attr :up_next_index, :integer, default: nil
  attr :elapsed_percent, :integer, required: true
  attr :countdown_label, :string, required: true
  attr :holding_label, :string, required: true
  attr :embedded, :boolean, default: false
  attr :target, :any, default: nil

  def queue_card(assigns) do
    ~H"""
    <div class={[!@embedded && "card bg-base-200 border border-base-300"]}>
      <div class={[!@embedded && "card-body p-4 gap-3", @embedded && "space-y-1"]}>
        <div :if={!@embedded} class="flex items-center justify-between">
          <h2 class="text-base font-semibold">Playlist</h2>
          <span class="text-xs opacity-60">
            <%= if @count == 0 do %>
              empty
            <% else %>
              {@count} {ngettext("mode", "modes", @count)} · every {@interval_label}
              <span :if={@transition_label != ""}> · {@transition_label} fade</span>
            <% end %>
          </span>
        </div>

        <div :if={@embedded} class="flex items-center justify-between gap-2 pb-0.5">
          <h2 class="text-sm font-semibold leading-none">Playlist</h2>
          <span :if={@count > 0} class="text-xs opacity-60 shrink-0">
            {@count} {ngettext("mode", "modes", @count)}
          </span>
        </div>

        <div
          :if={@count == 0}
          class={[
            "border-2 border-dashed border-base-content/20 rounded-lg text-center text-sm opacity-70",
            @embedded && "p-3",
            !@embedded && "p-6"
          ]}
        >
          <div class="font-semibold mb-1">Nothing in playlist</div>
          The wall keeps showing {@holding_label}. Add modes with ＋ Playlist.
        </div>

        <div :if={@count > 0} class="flex flex-col gap-0.5">
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

        <p :if={@count == 1} class="text-xs opacity-60 pt-0.5 leading-tight">
          One mode holds steady — add another to start rotating.
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
      "group relative flex items-center gap-1 rounded-md border px-2 py-1 min-h-[1.75rem]",
      @live? && "border-[#00d390] bg-[#00d390]/10",
      !@live? && "border-base-300 bg-base-100"
    ]}>
      <span class="w-4 text-center text-[11px] opacity-60 shrink-0 leading-none">{@idx + 1}</span>
      <span class="w-1 self-stretch min-h-[1rem] rounded shrink-0" style={"background-color: #{@entry.accent_color}"} />
      <div
        class="flex-1 min-w-0 font-semibold text-sm truncate leading-tight"
        title={"#{@entry.app_name} · #{@entry.mode_name}"}
      >
        {@entry.mode_name}
      </div>

      <.live_badge :if={@live?} />
      <span :if={@up_next? and not @live?} class="text-xs opacity-70 whitespace-nowrap shrink-0">
        up next · {@countdown_label}
      </span>

      <div class={[
        "flex items-center gap-0.5 shrink-0",
        "max-[699px]:opacity-100 max-[699px]:pointer-events-auto",
        "opacity-0 pointer-events-none",
        "group-hover:opacity-100 group-hover:pointer-events-auto",
        "group-focus-within:opacity-100 group-focus-within:pointer-events-auto"
      ]}>
        <button
          class="btn btn-ghost btn-xs btn-square min-h-8 min-w-8"
          phx-click="queue_move"
          phx-value-index={@idx}
          phx-value-dir="up"
          phx-target={@target}
          disabled={@idx == 0}
          aria-label="Move up"
        >
          <.console_icon_chevron_up class="w-3.5 h-3.5" />
        </button>
        <button
          class="btn btn-ghost btn-xs btn-square min-h-8 min-w-8"
          phx-click="queue_move"
          phx-value-index={@idx}
          phx-value-dir="down"
          phx-target={@target}
          disabled={@idx == @count - 1}
          aria-label="Move down"
        >
          <.console_icon_chevron_down class="w-3.5 h-3.5" />
        </button>
        <button
          class="btn btn-ghost btn-xs btn-square min-h-8 min-w-8"
          phx-click="queue_remove"
          phx-value-index={@idx}
          phx-target={@target}
          aria-label="Remove from playlist"
        >
          <.console_icon_x class="w-3.5 h-3.5" />
        </button>
      </div>

      <div
        :if={@live?}
        class="absolute bottom-0 left-0 h-[2px] bg-[#00d390] rounded-bl-md"
        style={"width: #{@elapsed_percent}%"}
      />
    </div>
    """
  end

  attr :mode, :map, required: true
  attr :app_module, :atom, required: true
  attr :live?, :boolean, default: false
  attr :mask?, :boolean, default: false
  attr :queued_pos, :integer, default: nil
  attr :queueable?, :boolean, default: true
  attr :mask_eligible?, :boolean, default: false
  attr :play_now_title, :string, default: "Show on the wall"
  attr :stop_takeover?, :boolean, default: false
  attr :target, :any, default: nil

  def mode_tile(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 overflow-hidden">
      <div class="h-1" style={"background-color: #{@mode.accent_color}"} />
      <div class="card-body p-2">
        <div class="flex items-center gap-2 min-w-0">
          <h3 class="font-semibold text-sm leading-tight truncate min-w-0 flex-1">{@mode.name}</h3>
          <div class="flex items-center gap-1 shrink-0">
            <.live_badge :if={@live?} />
            <.mask_badge :if={@mask?} />
            <span :if={@queued_pos} class="badge badge-outline badge-xs">Nr. {@queued_pos}</span>
            <span :if={Map.get(@mode, :builtin) == false} class="badge badge-outline badge-xs opacity-70">
              yours
            </span>
            <button
              :if={@stop_takeover?}
              class="btn btn-sm btn-square btn-error min-h-9 min-w-9"
              phx-click="stop_takeover"
              phx-value-app={Atom.to_string(@app_module)}
              phx-value-mode_id={@mode.id}
              phx-target={@target}
              title="Stop"
              aria-label="Stop"
            >
              <.console_icon_stop class="w-4 h-4" />
            </button>
            <button
              :if={!@stop_takeover?}
              class="btn btn-sm btn-square min-h-9 min-w-9"
              phx-click="play_now"
              phx-value-app={Atom.to_string(@app_module)}
              phx-value-mode_id={@mode.id}
              phx-target={@target}
              title={@play_now_title}
              aria-label={@play_now_title}
            >
              <.console_icon_play class="w-4 h-4" />
            </button>
            <button
              :if={@mask_eligible? && !@stop_takeover?}
              class="btn btn-sm btn-square btn-ghost min-h-9 min-w-9 opacity-70 hover:opacity-100"
              phx-click="start_as_mask"
              phx-value-module={Atom.to_string(@app_module)}
              phx-value-mode_id={@mode.id}
              phx-target={@target}
              title="Als Mask-App starten"
              aria-label="Als Mask-App starten"
            >
              <.console_icon_mask class="w-4 h-4" />
            </button>
            <button
              :if={@queueable?}
              class={[
                "btn btn-sm btn-square min-h-9 min-w-9",
                @queued_pos && "btn-primary bg-[#6d7cff] border-[#6d7cff]"
              ]}
              phx-click="queue_toggle"
              phx-value-app={Atom.to_string(@app_module)}
              phx-value-mode_id={@mode.id}
              phx-target={@target}
              title={if @queued_pos, do: "In playlist", else: "Add to playlist"}
              aria-label={if @queued_pos, do: "In playlist", else: "Add to playlist"}
            >
              <.console_icon_check :if={@queued_pos} class="w-4 h-4" />
              <.console_icon_plus :if={!@queued_pos} class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true

  def soon_tile(assigns) do
    ~H"""
    <div class="card border-2 border-dashed border-base-content/20 min-h-[3.5rem] flex items-center justify-center text-center p-2 text-sm opacity-50">
      {@label} — soon
    </div>
    """
  end

  attr :front_app, :map, default: nil
  attr :mask_app, :map, default: nil
  attr :target, :any, default: nil

  def app_slots(assigns) do
    ~H"""
    <div class="divide-y divide-base-300">
      <%!-- Front App Slot --%>
      <div class="flex items-center gap-3 py-3">
        <div class="w-16 shrink-0">
          <span class="text-[10px] uppercase tracking-wider font-semibold opacity-50">Front</span>
        </div>
        <%= if @front_app do %>
          <span class="w-2 h-2 rounded-full bg-[#00d390] shrink-0" />
          <span class="font-medium flex-1 min-w-0 truncate">{@front_app.name}</span>
          <span class="badge badge-sm bg-[#00d390] text-black border-0 shrink-0">Aktiv</span>
          <button
            class="btn btn-sm btn-error btn-square min-h-9 min-w-9 shrink-0"
            phx-click="stop_front_app"
            phx-target={@target}
            title="Front-App beenden"
            aria-label="Front-App beenden"
          >
            <.console_icon_stop class="w-4 h-4" />
          </button>
        <% else %>
          <span class="w-2 h-2 rounded-full bg-base-content/20 shrink-0" />
          <span class="flex-1 text-sm opacity-50 italic">Leer</span>
        <% end %>
      </div>

      <%!-- Mask App Slot --%>
      <div class="flex items-center gap-3 py-3">
        <div class="w-16 shrink-0">
          <span class="text-[10px] uppercase tracking-wider font-semibold opacity-50">Mask</span>
        </div>
        <%= if @mask_app do %>
          <span class="w-2 h-2 rounded-full bg-base-content/60 shrink-0" />
          <span class="font-medium flex-1 min-w-0 truncate">{@mask_app.name}</span>
          <span class="badge badge-neutral badge-sm shrink-0">Mask</span>
          <button
            class="btn btn-sm btn-error btn-square min-h-9 min-w-9 shrink-0"
            phx-click="stop_mask_app"
            phx-target={@target}
            title="Mask-App beenden"
            aria-label="Mask-App beenden"
          >
            <.console_icon_stop class="w-4 h-4" />
          </button>
        <% else %>
          <span class="w-2 h-2 rounded-full bg-base-content/20 shrink-0" />
          <span class="flex-1 text-sm opacity-50 italic">Keine Mask aktiv</span>
        <% end %>
      </div>
    </div>
    """
  end

  def live_badge(assigns) do
    ~H"""
    <span class="badge badge-sm bg-[#00d390] text-black border-0 font-semibold">FRONT</span>
    """
  end

  def mask_badge(assigns) do
    ~H"""
    <span class="badge badge-sm bg-[#a855f7] text-white border-0 font-semibold">MASK</span>
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
  attr :embedded, :boolean, default: false
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
    <div
      :if={@now_playing && @live}
      id={"now-playing-#{@id_suffix}"}
      class={[
        @embedded && "space-y-3",
        !@embedded && "card bg-base-200 border border-base-300 shadow-sm"
      ]}
    >
      <div class={[!@embedded && "card-body p-4 gap-3", @embedded && "space-y-3"]}>
        <div :if={!@embedded} class="flex items-center justify-between gap-3">
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
                    phx-hook="NowPlayingSlider"
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
                        min={now_playing_number_min(spec)}
                        max={spec.max}
                        step={now_playing_number_step(spec)}
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
                      <div
                        :if={is_nil(auto_spec) and spec[:auto_spacer]}
                        class="flex items-center gap-1.5 shrink-0 invisible pointer-events-none select-none"
                        aria-hidden="true"
                      >
                        <span class="text-[11px]">Auto</span>
                        <span class="toggle toggle-sm shrink-0"></span>
                      </div>
                    </div>
                  </div>

                  <div
                    :if={nested != []}
                    class="ml-3 space-y-1.5 border-l border-base-300 pl-3"
                  >
                    <div
                      :for={sub <- nested}
                      id={"now-playing-slider-#{sub.key}-#{@id_suffix}"}
                      phx-hook="NowPlayingSlider"
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
                            Map.get(@now_playing.effective, spec.key) == elem(option, 0) && "btn-primary",
                            now_playing_disabled?(@now_playing, spec) && "opacity-40 pointer-events-none"
                          ]}
                          phx-click="now_playing_choice"
                          phx-value-key={spec.key}
                          phx-value-index={idx}
                          phx-target={@target}
                          disabled={now_playing_disabled?(@now_playing, spec)}
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
        <div
          :if={@now_playing.meta != []}
          class="rounded-lg bg-base-300/40 p-3 console-mono text-xs space-y-0.5"
        >
          <div :for={line <- @now_playing.meta}>{line}</div>
        </div>

        <div :if={@has_tweakables} class="flex flex-wrap gap-2 pt-3 border-t border-base-300">
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

    rows =
      control_tweakables
      |> Enum.reject(&(&1.key in companion_keys or &1.key in nested_keys))
      |> Enum.map(fn
        %{type: :slider} = spec ->
          auto_spec =
            case spec[:auto_key] do
              nil -> nil
              key -> Map.get(by_key, key)
            end

          {:slider, spec, auto_spec, []}

        spec ->
          {:control, spec}
      end)

    # Nest Range/Interval under the last slider disabled by that Auto
    # (Translate: under Y, not between X and Y).
    Enum.reduce(nested_by_auto, rows, fn {auto_key, nested}, acc ->
      case find_auto_nested_anchor_index(acc, auto_key) do
        nil ->
          acc

        idx ->
          List.update_at(acc, idx, fn {:slider, spec, auto_spec, _} ->
            {:slider, spec, auto_spec, nested}
          end)
      end
    end)
  end

  defp find_auto_nested_anchor_index(rows, auto_key) do
    rows
    |> Enum.with_index()
    |> Enum.filter(fn
      {{:slider, spec, _auto, _}, _} ->
        spec[:auto_key] == auto_key or
          match?({^auto_key, _}, spec[:disabled_when])

      _ ->
        false
    end)
    |> List.last()
    |> case do
      {_, idx} -> idx
      nil -> nil
    end
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
      is_number(value) ->
        format_tweak_number_raw(Float.round(value * 1.0, 1))

      true ->
        format_tweak_number_raw(value)
    end
  end

  # Arrow keys on the number box step in whole units; the range keeps fine steps.
  defp now_playing_number_step(%{key: :zoom_base}), do: 1
  defp now_playing_number_step(%{step: step}), do: step

  # HTML number stepping is min + n*step — with min=0.7 and step=1 you get 1.7, 2.7…
  defp now_playing_number_min(%{key: :zoom_base}), do: 1
  defp now_playing_number_min(%{min: min}), do: min

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
      %{key: key} -> validate_formula(now_playing_formula_value(effective, key)) == :ok
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
    case validate_formula(formula) do
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

  defp validate_formula(formula) when is_binary(formula) do
    case Program.parse(formula) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp validate_formula(_), do: :error

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

  attr :show, :boolean, required: true
  attr :target, :any, default: nil

  def custom_transition_modal(assigns) do
    ~H"""
    <div :if={@show} class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Custom fade</h3>
        <form phx-submit="save_custom_transition" phx-target={@target} class="space-y-4 mt-2">
          <div class="flex gap-2 items-center">
            <input
              type="number"
              name="value"
              min="0"
              step="0.1"
              value="1"
              class="input input-bordered flex-1"
            />
            <span class="text-sm opacity-70 shrink-0">seconds total</span>
          </div>
          <div class="modal-action mt-0">
            <button type="button" class="btn btn-ghost" phx-click="close_custom_transition" phx-target={@target}>
              Cancel
            </button>
            <button type="submit" class="btn btn-primary bg-[#6d7cff] border-[#6d7cff]">Set</button>
          </div>
        </form>
      </div>
      <button type="button" class="modal-backdrop" phx-click="close_custom_transition" phx-target={@target} />
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

  def transition_label(seconds) when seconds <= 0, do: ""

  def transition_label(seconds) do
    case Enum.find(transition_presets(), fn {_l, s} -> s == seconds end) do
      {label, _} -> label
      nil -> humanize_transition(seconds)
    end
  end

  defp transport_timing_summary(interval_label, transition_label) do
    fade =
      if transition_label in ["", "Off"] do
        "no fade"
      else
        "#{transition_label} fade"
      end

    "#{interval_label} · #{fade}"
  end

  def humanize_transition(seconds) when is_float(seconds) do
    if seconds == trunc(seconds) do
      "#{trunc(seconds)} s"
    else
      "#{seconds} s"
    end
  end

  def humanize_transition(seconds) when is_integer(seconds), do: humanize_transition(seconds * 1.0)

  attr :class, :string, default: "w-5 h-5"

  def console_icon_dots_vertical(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path
        fill-rule="evenodd"
        d="M12 3.75a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm0 6.75a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm0 6.75a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  def console_icon_cog(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path
        fill-rule="evenodd"
        d="M11.078 2.25c-.917 0-1.699.663-1.85 1.567L9.05 4.889c-.02.12-.115.26-.297.348a7.493 7.493 0 0 0-.986.57c-.166.115-.334.126-.45.083L6.3 5.508a1.875 1.875 0 0 0-2.282.819l-.922 1.597a1.875 1.875 0 0 0 .432 2.385l.84.692c.095.078.17.229.154.43a7.598 7.598 0 0 0 0 1.139c.015.2-.059.352-.153.43l-.841.692a1.875 1.875 0 0 0-.432 2.385l.922 1.597a1.875 1.875 0 0 0 2.282.818l1.019-.382c.115-.043.283-.031.45.082.312.214.641.405.985.57.182.088.277.228.297.35l.178 1.071c.151.904.933 1.567 1.85 1.567h1.844c.916 0 1.699-.663 1.85-1.567l.178-1.072c.02-.12.114-.26.297-.349.344-.165.673-.356.985-.57.167-.114.335-.125.45-.082l1.02.382a1.875 1.875 0 0 0 2.28-.819l.923-1.597a1.875 1.875 0 0 0-.432-2.385l-.84-.692c-.094-.078-.17-.229-.154-.43a7.598 7.598 0 0 0 0-1.139c-.016-.2.059-.352.153-.43l.84-.692c.708-.582.891-1.59.433-2.385l-.922-1.597a1.875 1.875 0 0 0-2.282-.818l-1.02.382c-.114.043-.282.031-.449-.083a7.49 7.49 0 0 0-.985-.57c-.183-.087-.277-.227-.297-.348l-.179-1.072a1.875 1.875 0 0 0-1.85-1.567h-1.843ZM12 15.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5Z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  def console_icon_play(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.347c1.295.712 1.295 2.573 0 3.286L7.28 19.99c-1.25.687-2.779-.217-2.779-1.643V5.653Z" clip-rule="evenodd" />
    </svg>
    """
  end

  def console_icon_pause(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M6.75 5.25a.75.75 0 0 1 .75-.75h2.25a.75.75 0 0 1 .75.75v13.5a.75.75 0 0 1-.75.75H7.5a.75.75 0 0 1-.75-.75V5.25Zm7.5 0A.75.75 0 0 1 15 4.5h2.25a.75.75 0 0 1 .75.75v13.5a.75.75 0 0 1-.75.75H15a.75.75 0 0 1-.75-.75V5.25Z" clip-rule="evenodd" />
    </svg>
    """
  end

  def console_icon_plus(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M12 3.75a.75.75 0 0 1 .75.75v6.75h6.75a.75.75 0 0 1 0 1.5h-6.75v6.75a.75.75 0 0 1-1.5 0v-6.75H4.5a.75.75 0 0 1 0-1.5h6.75V4.5a.75.75 0 0 1 .75-.75Z" clip-rule="evenodd" />
    </svg>
    """
  end

  def console_icon_check(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.739a.75.75 0 0 1 1.04-.208Z" clip-rule="evenodd" />
    </svg>
    """
  end

  def console_icon_stop(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M4.5 7.5a3 3 0 0 1 3-3h9a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-9a3 3 0 0 1-3-3v-9Z" clip-rule="evenodd" />
    </svg>
    """
  end

  def console_icon_chevron_up(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M11.47 7.72a.75.75 0 0 1 1.06 0l7.5 7.5a.75.75 0 1 1-1.06 1.06L12 9.31l-6.97 6.97a.75.75 0 0 1-1.06-1.06l7.5-7.5Z" clip-rule="evenodd" />
    </svg>
    """
  end

  def console_icon_chevron_down(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M12.53 16.28a.75.75 0 0 1-1.06 0l-7.5-7.5a.75.75 0 1 1 1.06-1.06L12 14.69l6.97-6.97a.75.75 0 0 1 1.06 1.06l-7.5 7.5Z" clip-rule="evenodd" />
    </svg>
    """
  end

  def console_icon_x(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path fill-rule="evenodd" d="M5.47 5.47a.75.75 0 0 1 1.06 0L12 10.94l5.47-5.47a.75.75 0 1 1 1.06 1.06L13.06 12l5.47 5.47a.75.75 0 1 1-1.06 1.06L12 13.06l-5.47 5.47a.75.75 0 0 1-1.06-1.06L10.94 12 5.47 6.53a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
    </svg>
    """
  end

  attr :class, :string, default: "w-5 h-5"

  def console_icon_mask(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path d="M12 3a9 9 0 0 0 0 18V3Z" />
      <path fill-rule="evenodd" d="M12 2.25C6.615 2.25 2.25 6.615 2.25 12S6.615 21.75 12 21.75 21.75 17.385 21.75 12 17.385 2.25 12 2.25Zm0 1.5a8.25 8.25 0 1 1 0 16.5 8.25 8.25 0 0 1 0-16.5Z" clip-rule="evenodd" />
    </svg>
    """
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
