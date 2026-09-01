defmodule OctopusWeb.StudioLive do
  @moduledoc """
  The composer's desk: one page where the picture is watched and the sound is
  steered.

  This is the first stage of the studio described in `docs/pixelfun-av/03-ui.md`
  — transport, stage, the probes that bridge picture and sound, and the sound
  sources that exist today. The step grid and the modulation matrix follow; the
  scene itself is referenced, not edited here, so there is only ever one scene
  editor.
  """

  use OctopusWeb, :live_view

  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun
  alias Octopus.Installation
  alias Octopus.Sound
  alias Octopus.Sound.{Clock, Composition, Engine, Patch, Pattern, Probes, RingChase, Scheduler}
  alias OctopusWeb.PixelsLive

  # A meter that falls to silence in about half a second reads as a level
  # rather than as a flashing light.
  @level_decay 0.82
  @tick_ms 80
  @probe_interval_ms 100

  @synths ["pc_ping", "pc_pluck", "pc_click", "pc_drone"]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Clock.subscribe()
      Probes.subscribe()
      Engine.subscribe_notes()
      Patch.subscribe()
      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok,
     socket
     |> assign(
       preview?: Application.get_env(:octopus, :show_sim_preview, true),
       panels: Installation.num_panels(),
       synths: @synths,
       probes: [],
       # Monotonic time is signed and starts far below zero, so a zero here
       # would keep the throttle below its own threshold forever.
       probes_at: System.monotonic_time(:millisecond) - @probe_interval_ms,
       levels: %{},
       position:
         safe(&Clock.position/0, %{bar: 1, beat: 1, step: 1, bpm: 120.0, playing?: false}),
       engine: safe(&Sound.engine/0, nil),
       chase: chase_state(),
       metronome?: metronome_running?(),
       scene: scene(),
       pattern: safe(&Patch.pattern/0, Pattern.new()),
       patch_slot: safe(&Patch.slot/0, :a),
       brush: 1,
       synths: Pattern.synths(),
       compositions: safe(&Composition.list/0, []),
       composition_name: ""
     )}
  end

  # -- Events ---------------------------------------------------------------

  @impl true
  def handle_event("toggle_play", _params, socket) do
    {:noreply, assign(socket, position: Clock.toggle())}
  end

  def handle_event("set_bpm", %{"bpm" => bpm}, socket) do
    case Float.parse(to_string(bpm)) do
      {bpm, _} when bpm > 0 -> {:noreply, assign(socket, position: Clock.set_bpm(bpm))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("panic", _params, socket) do
    Sound.panic()
    {:noreply, assign(socket, levels: %{})}
  end

  def handle_event("toggle_metronome", _params, socket) do
    on? = not socket.assigns.metronome?
    Sound.metronome(on?)
    {:noreply, assign(socket, metronome?: on?)}
  end

  def handle_event("toggle_chase", _params, socket) do
    RingChase.enable(not socket.assigns.chase.enabled?)
    {:noreply, assign(socket, chase: chase_state())}
  end

  def handle_event("configure_chase", params, socket) do
    opts =
      []
      |> put_option(params, "synth", &(&1 in @synths and {:ok, &1}))
      |> put_option(params, "duration_ms", &parse_number/1)
      |> put_option(params, "min_rise", &parse_number/1)

    if opts != [], do: RingChase.configure(opts)
    {:noreply, assign(socket, chase: chase_state())}
  end

  def handle_event("set_brush", %{"panel" => panel}, socket) do
    {:noreply, assign(socket, brush: String.to_integer(panel))}
  end

  def handle_event("cell", %{"slot" => slot, "step" => step}, socket) do
    slot_id = String.to_integer(slot)
    step = String.to_integer(step)
    brush = socket.assigns.brush

    Patch.update(&Pattern.put_step(&1, slot_id, step, brush))
    {:noreply, socket}
  end

  def handle_event("toggle_mute", %{"slot" => slot}, socket) do
    Patch.update(&Pattern.toggle_mute(&1, String.to_integer(slot)))
    {:noreply, socket}
  end

  def handle_event("clear_slot", %{"slot" => slot}, socket) do
    Patch.update(&Pattern.clear_slot(&1, String.to_integer(slot)))
    {:noreply, socket}
  end

  def handle_event("slot_synth", %{"slot" => slot, "synth" => synth}, socket) do
    if synth in socket.assigns.synths do
      Patch.update(&Pattern.configure_slot(&1, String.to_integer(slot), %{synth: synth}))
    end

    {:noreply, socket}
  end

  def handle_event("switch_ab", _params, socket) do
    Patch.switch()
    {:noreply, socket}
  end

  def handle_event("copy_ab", _params, socket) do
    Patch.copy_to_other()
    {:noreply, socket}
  end

  def handle_event("composition_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, composition_name: name)}
  end

  def handle_event("save", _params, socket) do
    name = String.trim(socket.assigns.composition_name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Die Komposition braucht einen Namen.")}
    else
      case Composition.save(name, socket.assigns.pattern, save_opts(socket)) do
        {:ok, _composition} ->
          {:noreply,
           socket
           |> assign(compositions: Composition.list())
           |> put_flash(:info, "„#{name}\" gespeichert.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Speichern fehlgeschlagen.")}
      end
    end
  end

  def handle_event("take", _params, socket) do
    {:ok, composition} = Composition.take(socket.assigns.pattern, save_opts(socket))

    {:noreply,
     socket
     |> assign(compositions: Composition.list())
     |> put_flash(:info, "Festgehalten als „#{composition.name}\".")}
  end

  def handle_event("load", %{"id" => id}, socket) do
    case Composition.load(String.to_integer(id)) do
      {:ok, composition} ->
        Clock.set_bpm(composition.bpm)

        {:noreply,
         socket
         |> assign(composition_name: composition.name)
         |> put_flash(:info, "„#{composition.name}\" geladen.")}

      :error ->
        {:noreply, put_flash(socket, :error, "Komposition nicht gefunden.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Composition.delete(String.to_integer(id))
    {:noreply, assign(socket, compositions: Composition.list())}
  end

  # -- Messages -------------------------------------------------------------

  @impl true
  def handle_info({:sound_clock, position}, socket) do
    {:noreply, assign(socket, position: position)}
  end

  # Probes arrive with every rendered frame. The eye cannot follow 30 updates a
  # second and the socket should not carry them, so only every tenth is shown.
  def handle_info({:pixel_probes, %{values: values}}, socket) do
    now = System.monotonic_time(:millisecond)

    if now - socket.assigns.probes_at >= @probe_interval_ms do
      {:noreply, assign(socket, probes: values, probes_at: now)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:sound_note, %{channel: channel, velocity: velocity}}, socket) do
    levels = Map.update(socket.assigns.levels, channel, velocity, &max(&1, velocity))
    {:noreply, assign(socket, levels: levels)}
  end

  def handle_info({:sound_patch, %{pattern: pattern, slot: slot}}, socket) do
    {:noreply, assign(socket, pattern: pattern, patch_slot: slot)}
  end

  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(levels: decay(socket.assigns.levels))
     |> assign(scene: scene())}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # -- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-3 space-y-3 max-w-[1400px] mx-auto">
      <.transport position={@position} engine={@engine} />

      <.library
        compositions={@compositions}
        composition_name={@composition_name}
        patch_slot={@patch_slot}
      />

      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_320px] gap-3">
        <.stage
          panels={@panels}
          probes={@probes}
          levels={@levels}
          preview?={@preview?}
          socket={@socket}
        />

        <div class="space-y-3">
          <.scene_card scene={@scene} />
          <.sound_card chase={@chase} metronome?={@metronome?} synths={@synths} />
        </div>
      </div>

      <.grid
        pattern={@pattern}
        panels={@panels}
        brush={@brush}
        synths={@synths}
        playhead={playhead(@position, @pattern)}
      />
    </div>
    """
  end

  attr :compositions, :list, required: true
  attr :composition_name, :string, required: true
  attr :patch_slot, :atom, required: true

  defp library(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 flex-row flex-wrap items-center gap-2">
        <form phx-change="composition_name" class="contents">
          <input
            type="text"
            name="name"
            value={@composition_name}
            placeholder="Name der Komposition"
            class="input input-bordered input-sm w-56"
          />
        </form>
        <button class="btn btn-sm" phx-click="save">Speichern</button>
        <button class="btn btn-sm btn-ghost" phx-click="take" title="Moment festhalten">
          Take
        </button>

        <div class="join">
          <button
            class={["btn btn-sm join-item", @patch_slot == :a && "btn-active"]}
            phx-click="switch_ab"
            disabled={@patch_slot == :a}
          >
            A
          </button>
          <button
            class={["btn btn-sm join-item", @patch_slot == :b && "btn-active"]}
            phx-click="switch_ab"
            disabled={@patch_slot == :b}
          >
            B
          </button>
        </div>
        <button
          class="btn btn-sm btn-ghost"
          phx-click="copy_ab"
          title="Live-Muster in die andere Seite kopieren"
        >
          A→B kopieren
        </button>

        <div :if={@compositions != []} class="flex items-center gap-1 flex-wrap ml-auto">
          <span class="text-xs uppercase tracking-wider opacity-60">Laden</span>
          <span :for={composition <- @compositions} class="join">
            <button class="btn btn-xs join-item" phx-click="load" phx-value-id={composition.id}>
              {composition.name}
            </button>
            <button
              class="btn btn-xs join-item btn-ghost"
              phx-click="delete"
              phx-value-id={composition.id}
              data-confirm={"„#{composition.name}\" löschen?"}
            >
              ×
            </button>
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :pattern, :map, required: true
  attr :panels, :integer, required: true
  attr :brush, :integer, required: true
  attr :synths, :list, required: true
  attr :playhead, :integer, required: true

  defp grid(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 gap-3">
        <div class="flex items-center gap-3 flex-wrap">
          <h2 class="text-sm font-semibold uppercase tracking-wider">Grid</h2>
          <div class="flex items-center gap-1 flex-wrap">
            <span class="text-xs opacity-60 mr-1">Panel</span>
            <button
              :for={panel <- 1..@panels}
              class={[
                "btn btn-xs w-8",
                panel == @brush && "btn-warning",
                panel != @brush && "btn-ghost"
              ]}
              phx-click="set_brush"
              phx-value-panel={panel}
            >
              {panel}
            </button>
          </div>
          <span class="text-[11px] opacity-60">
            Klick setzt den Schritt auf das gewählte Panel — nochmal derselbe Klick löscht ihn.
          </span>
        </div>

        <div class="overflow-x-auto">
          <table class="border-separate border-spacing-1">
            <thead>
              <tr>
                <th class="w-56"></th>
                <th
                  :for={step <- 0..(@pattern.steps - 1)}
                  class="w-7 text-[10px] font-mono opacity-50"
                >
                  {if rem(step, 4) == 0, do: div(step, 4) + 1, else: "·"}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={slot <- @pattern.slots}>
                <th class="text-left font-normal">
                  <div class="flex items-center gap-1">
                    <button
                      class={[
                        "btn btn-xs w-7",
                        slot.muted? && "btn-error",
                        !slot.muted? && "btn-ghost"
                      ]}
                      phx-click="toggle_mute"
                      phx-value-slot={slot.id}
                      title="Mute"
                    >
                      {slot.id}
                    </button>
                    <form phx-change="slot_synth" class="contents">
                      <input type="hidden" name="slot" value={slot.id} />
                      <select name="synth" class="select select-bordered select-xs w-28">
                        <option :for={synth <- @synths} value={synth} selected={synth == slot.synth}>
                          {synth}
                        </option>
                      </select>
                    </form>
                    <button
                      class="btn btn-xs btn-ghost"
                      phx-click="clear_slot"
                      phx-value-slot={slot.id}
                      title="Zeile leeren"
                    >
                      ⌫
                    </button>
                  </div>
                </th>
                <td :for={step <- 0..(@pattern.steps - 1)}>
                  <button
                    class={
                      cell_class(Map.get(slot.steps, step), step == @playhead, rem(step, 4) == 0)
                    }
                    phx-click="cell"
                    phx-value-slot={slot.id}
                    phx-value-step={step}
                  >
                    {cell_label(Map.get(slot.steps, step))}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr :position, :map, required: true
  attr :engine, :map, default: nil

  defp transport(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 flex-row flex-wrap items-center gap-3">
        <button class={["btn btn-sm", @position.playing? && "btn-primary"]} phx-click="toggle_play">
          {if @position.playing?, do: "⏸ Stop", else: "▶ Play"}
        </button>

        <form phx-change="set_bpm" class="flex items-center gap-2">
          <label class="text-xs uppercase tracking-wider opacity-60" for="bpm">Tempo</label>
          <input
            id="bpm"
            type="number"
            name="bpm"
            min="20"
            max="300"
            step="0.5"
            value={Float.round(@position.bpm * 1.0, 1)}
            class="input input-bordered input-sm w-24 font-mono"
          />
        </form>

        <div class="flex flex-col">
          <span class="text-xs uppercase tracking-wider opacity-60">Position</span>
          <span class="font-mono tabular-nums">
            {format_position(@position)}
          </span>
        </div>

        <div class="flex flex-col">
          <span class="text-xs uppercase tracking-wider opacity-60">Engine</span>
          <span class="font-mono text-sm">{engine_name(@engine)}</span>
        </div>

        <span class={["badge badge-sm", timing_class(@engine)]}>{timing_label(@engine)}</span>

        <button class="btn btn-sm btn-error btn-outline ml-auto" phx-click="panic">Panic</button>
      </div>
    </div>
    """
  end

  attr :panels, :integer, required: true
  attr :probes, :list, required: true
  attr :levels, :map, required: true
  attr :preview?, :boolean, default: true
  attr :socket, :map, required: true

  defp stage(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 gap-3">
        <div :if={@preview?} class="h-64 rounded-lg overflow-hidden bg-black">
          {live_render(@socket, PixelsLive, id: "studio-preview", session: %{"embedded" => true})}
        </div>

        <div>
          <div class="text-xs uppercase tracking-wider opacity-60 mb-1">
            Probes — Formelwert je Panel
          </div>
          <div class="grid gap-1" style={"grid-template-columns: repeat(#{@panels}, minmax(0, 1fr))"}>
            <div :for={index <- 0..(@panels - 1)} class="flex flex-col items-center gap-1">
              <div class="w-full h-10 bg-base-300 rounded relative overflow-hidden">
                <div class="absolute inset-x-0 top-1/2 h-px bg-base-content/20" />
                <div
                  class="absolute left-0 right-0 bg-warning"
                  style={probe_bar_style(Enum.at(@probes, index))}
                />
              </div>
              <div class="w-full h-2.5 bg-base-300 rounded overflow-hidden">
                <div
                  class="h-full bg-info transition-[width] duration-75"
                  style={"width: #{round(Map.get(@levels, index + 1, 0.0) * 100)}%"}
                />
              </div>
              <span class="text-[10px] font-mono opacity-50">{index + 1}</span>
            </div>
          </div>
          <div class="text-[11px] opacity-50 mt-1">
            Balken: Formelwert −1…+1 · Linie darunter: Pegel des Lautsprechers an diesem Panel
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :scene, :map, default: nil

  defp scene_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 gap-2">
        <h2 class="text-sm font-semibold uppercase tracking-wider text-warning">Szene</h2>

        <%= if @scene do %>
          <div class="text-sm">{@scene.name}</div>
          <code class="text-xs bg-base-300 rounded p-2 block break-all">{@scene.program}</code>
          <.link navigate={~p"/"} class="btn btn-xs btn-ghost self-start">
            Im Foyer bearbeiten →
          </.link>
        <% else %>
          <p class="text-sm opacity-60">
            Kein Pixel Fun aktiv. Ohne laufende Szene gibt es keine Probes — und damit nichts,
            woran der Klang hängen könnte.
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :chase, :map, required: true
  attr :metronome?, :boolean, required: true
  attr :synths, :list, required: true

  defp sound_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 gap-3">
        <h2 class="text-sm font-semibold uppercase tracking-wider text-info">Klang</h2>

        <label class="flex items-center justify-between gap-2 cursor-pointer">
          <span class="text-sm">Metronom</span>
          <input
            type="checkbox"
            class="toggle toggle-sm"
            checked={@metronome?}
            phx-click="toggle_metronome"
          />
        </label>

        <div class="divider my-0" />

        <label class="flex items-center justify-between gap-2 cursor-pointer">
          <span class="text-sm font-medium">Ring-Chase</span>
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-info"
            checked={@chase.enabled?}
            phx-click="toggle_chase"
          />
        </label>
        <p class="text-[11px] opacity-60 -mt-1">
          Jedes Panel, dessen Formelwert durch null steigt, klingt auf seinem eigenen
          Lautsprecher. Braucht keinen Transport — das Bild ist die Uhr.
        </p>

        <form phx-change="configure_chase" class="space-y-2">
          <label class="form-control">
            <span class="label-text text-xs">Klang</span>
            <select name="synth" class="select select-bordered select-sm">
              <option :for={synth <- @synths} value={synth} selected={synth == @chase.synth}>
                {synth}
              </option>
            </select>
          </label>

          <label class="form-control">
            <span class="label-text text-xs">Länge {@chase.duration_ms} ms</span>
            <input
              type="range"
              name="duration_ms"
              min="40"
              max="2000"
              step="20"
              value={@chase.duration_ms}
              class="range range-xs"
            />
          </label>

          <label class="form-control">
            <span class="label-text text-xs">
              Mindeststeilheit {:erlang.float_to_binary(@chase.min_rise * 1.0, decimals: 3)}
            </span>
            <input
              type="range"
              name="min_rise"
              min="0.002"
              max="0.1"
              step="0.002"
              value={@chase.min_rise}
              class="range range-xs"
            />
          </label>
        </form>
      </div>
    </div>
    """
  end

  # -- Helpers --------------------------------------------------------------

  # Which column the transport is on right now, wrapped into the pattern.
  defp playhead(%{beats: beats} = position, pattern) do
    per_beat = Map.get(position, :steps_per_beat, 4)
    Integer.mod(floor(beats * per_beat), pattern.steps)
  end

  defp playhead(_position, _pattern), do: -1

  defp cell_label(nil), do: ""
  defp cell_label(%{panel: panel}), do: panel

  defp cell_class(cell, playhead?, beat_start?) do
    [
      "btn btn-xs w-7 min-h-0 h-7 p-0 font-mono",
      cell && "btn-info",
      is_nil(cell) && beat_start? && "btn-neutral btn-outline",
      is_nil(cell) && !beat_start? && "btn-ghost bg-base-300/60",
      playhead? && "ring-2 ring-warning"
    ]
  end

  defp save_opts(socket) do
    [
      bpm: socket.assigns.position.bpm,
      scene: socket.assigns.scene && socket.assigns.scene.program
    ]
  end

  defp format_position(%{bar: bar, beat: beat, step: step}) do
    "#{String.pad_leading(to_string(bar), 3, "0")}.#{beat}.#{step}"
  end

  defp engine_name(nil), do: "—"

  defp engine_name(%{module: module}) do
    module |> Module.split() |> List.last()
  end

  defp timing_label(%{capabilities: %{scheduling: :timestamped}}), do: "taktgenau"
  defp timing_label(%{capabilities: %{scheduling: :immediate}}), do: "best effort"
  defp timing_label(%{capabilities: %{scheduling: :none}}), do: "kein Klang"
  defp timing_label(_), do: "kein Klang"

  defp timing_class(%{capabilities: %{scheduling: :timestamped}}), do: "badge-success"
  defp timing_class(%{capabilities: %{scheduling: :immediate}}), do: "badge-warning"
  defp timing_class(%{capabilities: %{scheduling: :none}}), do: "badge-ghost"
  defp timing_class(_), do: "badge-ghost"

  # A probe reading is signed, so the bar grows from the middle line: up for
  # positive, down for negative, which is how the crossing is read.
  defp probe_bar_style(nil), do: "display: none"

  defp probe_bar_style(value) do
    height = min(abs(value), 1.0) * 50

    if value >= 0 do
      "bottom: 50%; height: #{height}%"
    else
      "top: 50%; height: #{height}%"
    end
  end

  defp decay(levels) do
    levels
    |> Enum.map(fn {channel, level} -> {channel, level * @level_decay} end)
    |> Enum.reject(fn {_channel, level} -> level < 0.02 end)
    |> Map.new()
  end

  # Read from the scheduler rather than remembered here, so a reconnect or a
  # second browser tab shows what is actually running.
  defp metronome_running? do
    safe(&Scheduler.metronome?/0, false)
  end

  defp chase_state do
    safe(
      fn ->
        state = :sys.get_state(RingChase)

        %{
          enabled?: state.enabled?,
          synth: state.synth,
          duration_ms: state.duration_ms,
          min_rise: state.min_rise
        }
      end,
      %{enabled?: false, synth: "pc_ping", duration_ms: 400, min_rise: 0.01}
    )
  end

  defp scene do
    Enum.find_value(AppSupervisor.running_apps(), fn
      {PixelFun, app_id} ->
        config = AppSupervisor.config(app_id)

        %{
          app_id: app_id,
          name: config[:live_scene_name] || "Pixel Fun",
          program: config[:program]
        }

      _other ->
        nil
    end)
  rescue
    _ -> nil
  end

  defp put_option(opts, params, key, parser) do
    with %{^key => raw} <- params,
         {:ok, value} <- parser.(raw) do
      Keyword.put(opts, String.to_existing_atom(key), value)
    else
      _ -> opts
    end
  end

  defp parse_number(raw) do
    case Float.parse(to_string(raw)) do
      {value, _} -> {:ok, value}
      :error -> :error
    end
  end

  # The sound stack is optional; the page has to survive it being switched off.
  defp safe(fun, fallback) do
    fun.()
  rescue
    _ -> fallback
  catch
    :exit, _ -> fallback
  end
end
