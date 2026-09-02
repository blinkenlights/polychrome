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

  alias Octopus.Sound.{
    Clock,
    Composition,
    Drone,
    Engine,
    Features,
    Matrix,
    Patch,
    Pattern,
    Probes,
    RingChase,
    Scheduler
  }

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
      Matrix.subscribe()
      Features.subscribe()
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
       composition_name: "",
       drone: drone_state(),
       features: %{level: 0.0, onset: 0.0},
       bindings: safe(&Matrix.list/0, []),
       matrix_filter: :all,
       new_source: nil,
       new_target: nil
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

    {:noreply,
     assign(socket,
       levels: %{},
       chase: chase_state(),
       drone: drone_state(),
       metronome?: metronome_running?(),
       position: safe(&Clock.position/0, socket.assigns.position)
     )}
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

  def handle_event("toggle_drone", _params, socket) do
    Drone.enable(not socket.assigns.drone.enabled?)
    {:noreply, assign(socket, drone: drone_state())}
  end

  def handle_event("matrix_filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, matrix_filter: String.to_existing_atom(filter))}
  end

  def handle_event("matrix_pick", params, socket) do
    {:noreply,
     socket
     |> assign(new_source: parse_key(params["source"]) || socket.assigns.new_source)
     |> assign(new_target: parse_key(params["target"]) || socket.assigns.new_target)}
  end

  def handle_event("matrix_add", _params, socket) do
    source = socket.assigns.new_source || default_source()
    target = socket.assigns.new_target || default_target()
    Matrix.add(source, target)

    {:noreply, socket}
  end

  def handle_event("matrix_amount", %{"binding" => id, "amount" => amount}, socket) do
    with {amount, _} <- Float.parse(to_string(amount)) do
      Matrix.set_amount(String.to_integer(id), amount)
    end

    {:noreply, socket}
  end

  def handle_event("matrix_curve", %{"binding" => id, "curve" => curve}, socket) do
    Matrix.set_curve(String.to_integer(id), String.to_existing_atom(curve))
    {:noreply, socket}
  end

  def handle_event("matrix_toggle", %{"id" => id}, socket) do
    Matrix.toggle(String.to_integer(id))
    {:noreply, socket}
  end

  def handle_event("matrix_remove", %{"id" => id}, socket) do
    Matrix.remove(String.to_integer(id))
    {:noreply, socket}
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

  def handle_info({:sound_matrix, bindings}, socket) do
    {:noreply, assign(socket, bindings: bindings)}
  end

  def handle_info({:sound_features, features}, socket) do
    {:noreply, assign(socket, features: features)}
  end

  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(levels: decay(socket.assigns.levels))
     |> assign(scene: scene())
     |> assign(drone: drone_state())}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # -- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-3 space-y-3 max-w-[1800px] mx-auto">
      <.transport position={@position} engine={@engine} />

      <.library
        compositions={@compositions}
        composition_name={@composition_name}
        patch_slot={@patch_slot}
      />

      <div class="grid grid-cols-1 xl:grid-cols-[280px_minmax(0,1fr)_300px] gap-3 items-start">
        <.scene_card scene={@scene} />

        <.stage
          panels={@panels}
          probes={@probes}
          levels={@levels}
          preview?={@preview?}
          chase={@chase}
          drone={@drone}
          socket={@socket}
        />

        <.sound_card
          chase={@chase}
          drone={@drone}
          metronome?={@metronome?}
          synths={@synths}
          scene={@scene}
        />
      </div>

      <.grid
        pattern={@pattern}
        panels={@panels}
        brush={@brush}
        synths={@synths}
        playhead={playhead(@position, @pattern)}
      />

      <.matrix
        bindings={@bindings}
        filter={@matrix_filter}
        new_source={@new_source || default_source()}
        new_target={@new_target || default_target()}
        probes={@probes}
        features={@features}
        drone={@drone}
        chase={@chase}
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
          title="Das laufende Muster in die andere Seite kopieren"
        >
          {if @patch_slot == :a, do: "A → B kopieren", else: "B → A kopieren"}
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
  attr :chase, :map, required: true
  attr :drone, :map, required: true
  attr :socket, :map, required: true

  defp stage(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 gap-3">
        <div
          :if={@preview?}
          class="studio-strip rounded-lg overflow-hidden bg-black"
          style={strip_aspect()}
        >
          {live_render(@socket, PixelsLive,
            id: "studio-preview",
            session: %{
              "embedded" => true,
              "chrome" => false,
              "view" => "Streifen (abgewickelt)"
            }
          )}
        </div>

        <div class="flex" style={strip_gap()}>
          <div :for={index <- 0..(@panels - 1)} class="flex-1 flex flex-col items-center gap-0.5">
            <div class="w-full h-3 bg-base-300 rounded-b overflow-hidden">
              <div
                class="h-full bg-info transition-[width] duration-75"
                style={"width: #{round(Map.get(@levels, index + 1, 0.0) * 100)}%"}
              />
            </div>
            <div class="w-full h-9 bg-base-300 rounded relative overflow-hidden">
              <div class="absolute inset-x-0 top-1/2 h-px bg-base-content/20" />
              <div
                class="absolute left-0 right-0 bg-warning"
                style={probe_bar_style(Enum.at(@probes, index))}
              />
            </div>
            <span class="text-[10px] font-mono opacity-50">{index + 1}</span>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_240px] gap-3">
          <.coupling_note chase={@chase} drone={@drone} />
          <.ring_view panels={@panels} probes={@probes} levels={@levels} />
        </div>
      </div>
    </div>
    """
  end

  attr :chase, :map, required: true
  attr :drone, :map, required: true

  defp coupling_note(assigns) do
    ~H"""
    <div class="rounded-lg bg-base-300/40 p-3 text-sm space-y-2">
      <div class="text-xs uppercase tracking-wider font-semibold text-info">
        Was gerade koppelt
      </div>
      <p class="text-[12px] opacity-70 leading-snug">
        Lesehilfe, keine Bedienung: welche Regel gerade Bild und Ton verbindet.
      </p>
      <dl class="text-[11px] font-mono space-y-1">
        <div :for={{label, value} <- coupling_lines(@chase, @drone)} class="flex gap-2">
          <dt class="opacity-50 w-10 shrink-0">{label}</dt>
          <dd class="opacity-80">{value}</dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :panels, :integer, required: true
  attr :probes, :list, required: true
  attr :levels, :map, required: true

  defp ring_view(assigns) do
    ~H"""
    <div class="rounded-lg bg-black p-2 flex flex-col items-center justify-center">
      <svg viewBox="0 0 200 200" class="w-full max-w-[220px]">
        <circle cx="100" cy="100" r="72" fill="none" stroke="#1A2331" stroke-width="1" />
        <circle cx="100" cy="100" r="20" fill="none" stroke="#151D29" stroke-width="1" />
        <text x="100" y="103" text-anchor="middle" font-size="8" fill="#3A4759">Publikum</text>

        <g :for={{position, index} <- Enum.with_index(ring_positions(@panels))}>
          <circle
            cx={position.x}
            cy={position.y}
            r={7 + abs(probe_at(@probes, index)) * 4}
            fill={probe_color(probe_at(@probes, index))}
            fill-opacity={0.25 + abs(probe_at(@probes, index)) * 0.75}
          />
          <circle
            :if={Map.get(@levels, index + 1, 0.0) > 0.02}
            cx={position.x}
            cy={position.y}
            r={12 + (1 - Map.get(@levels, index + 1, 0.0)) * 10}
            fill="none"
            stroke="#54D9E8"
            stroke-width="1.5"
            stroke-opacity={Map.get(@levels, index + 1, 0.0)}
          />
          <text
            x={position.label_x}
            y={position.label_y}
            text-anchor="middle"
            font-size="7"
            fill="#5A6678"
          >
            {index + 1}
          </text>
        </g>
      </svg>
      <div class="text-[10px] uppercase tracking-wider opacity-50 mt-1">
        Ringdraufsicht · Publikum in der Mitte
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
          <code class="text-[11px] leading-snug bg-base-300 rounded p-2 block break-all">
            {@scene.program}
          </code>
          <div class="grid grid-cols-3 gap-2 text-[11px]">
            <div :for={{label, value} <- @scene.values} class="bg-base-300/50 rounded p-1.5">
              <div class="opacity-60">{label}</div>
              <div class="font-mono tabular-nums">{value}</div>
            </div>
          </div>
          <.link navigate={~p"/"} class="btn btn-xs btn-ghost self-start">
            Im Foyer bearbeiten →
          </.link>
        <% else %>
          <p class="text-sm opacity-60">
            Auf der Wand läuft gerade kein Pixel Fun. Ohne Szene auf der Wand gibt es keine
            Probes — und damit nichts, woran der Klang hängen könnte.
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :chase, :map, required: true
  attr :drone, :map, required: true
  attr :metronome?, :boolean, required: true
  attr :synths, :list, required: true
  attr :scene, :map, default: nil

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
          <span class="text-sm font-medium">Drone</span>
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-info"
            checked={@drone.enabled?}
            phx-click="toggle_drone"
          />
        </label>
        <p class="text-[11px] opacity-60 -mt-1">
          Eine gehaltene Stimme je Panel, ihre Lautstärke folgt dem Formelwert dort.
          Der Akkord ändert sich, weil sich das Bild ändert.
        </p>

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
        <div
          :if={@scene && @scene.moving != []}
          class="text-[11px] rounded bg-warning/15 border border-warning/40 p-2 leading-snug"
        >
          <b>{Enum.join(@scene.moving, ", ")}</b> aktiv. Das dreht den Ring unter der
          Formel, also wird der Chase schneller und langsamer — er folgt dem Bild.
          Für gleichmäßiges Tempo im Foyer abschalten.
        </div>

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
            <span class="label-text text-xs">Länge {round(@chase.duration_ms)} ms</span>
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
              Mindeststeilheit {:erlang.float_to_binary(@chase.min_rise * 1.0, decimals: 4)}
            </span>
            <input
              type="range"
              name="min_rise"
              min="0.0005"
              max="0.05"
              step="0.0005"
              value={@chase.min_rise}
              class="range range-xs"
            />
          </label>
        </form>
      </div>
    </div>
    """
  end

  attr :bindings, :list, required: true
  attr :filter, :atom, required: true
  attr :new_source, :any, required: true
  attr :new_target, :any, required: true
  attr :probes, :list, required: true
  attr :features, :map, required: true
  attr :drone, :map, required: true
  attr :chase, :map, required: true

  defp matrix(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-3 gap-3">
        <div class="flex items-center gap-3 flex-wrap">
          <h2 class="text-sm font-semibold uppercase tracking-wider">Matrix</h2>
          <span class="text-[11px] opacity-60">
            Das Grid sagt, wann etwas klingt — die Matrix, was sich langsam verändert.
          </span>
          <div class="join ml-auto">
            <button
              :for={
                {filter, label} <- [
                  {:all, "Alle"},
                  {:sound_to_light, "Sound → Licht"},
                  {:light_to_sound, "Licht → Sound"},
                  {:score, "Partitur → beides"}
                ]
              }
              class={["btn btn-xs join-item", @filter == filter && "btn-active"]}
              phx-click="matrix_filter"
              phx-value-filter={filter}
            >
              {label}
            </button>
          </div>
        </div>

        <form phx-change="matrix_pick" class="flex items-end gap-2 flex-wrap">
          <label class="form-control">
            <span class="label-text text-xs">Quelle</span>
            <select name="source" class="select select-bordered select-sm">
              <option
                :for={{key, source} <- Enum.sort_by(Matrix.sources(), fn {_k, s} -> s.label end)}
                value={key_to_param(key)}
                selected={key == @new_source}
              >
                {source.label}
              </option>
            </select>
          </label>
          <span class="pb-2 opacity-50">→</span>
          <label class="form-control">
            <span class="label-text text-xs">Ziel</span>
            <select name="target" class="select select-bordered select-sm">
              <option
                :for={{key, target} <- Enum.sort_by(Matrix.targets(), fn {_k, t} -> t.label end)}
                value={key_to_param(key)}
                selected={key == @new_target}
              >
                {target.label}
              </option>
            </select>
          </label>
          <button type="button" class="btn btn-sm mb-0" phx-click="matrix_add">＋ Zeile</button>
        </form>

        <div :if={@bindings == []} class="text-sm opacity-60">
          Noch keine Kopplung. Zielbild 5 in einer Zeile: „Klang · Onsets" → „Szene ·
          Sättigung" — dann setzt jeder Anschlag einen Farbakzent.
        </div>

        <div :if={@bindings != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th class="w-32">Richtung</th>
                <th>Quelle</th>
                <th>Ziel</th>
                <th class="w-56">Betrag</th>
                <th class="w-28">Kurve</th>
                <th class="w-20"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={binding <- filtered_bindings(@bindings, @filter)}
                class={!binding.enabled? && "opacity-40"}
              >
                <td>
                  <span
                    class="inline-flex items-center gap-1"
                    title={direction_label(binding_direction(binding))}
                  >
                    <span
                      :for={{_role, class} <- direction_dots(binding_direction(binding))}
                      class={["w-2 h-2 rounded-sm inline-block", class]}
                    />
                    <span class="text-[10px] opacity-60 ml-1">
                      {direction_label(binding_direction(binding))}
                    </span>
                  </span>
                </td>
                <td class="text-sm">{source_label(binding.source)}</td>
                <td class="text-sm">{target_label(binding.target)}</td>
                <td>
                  <form phx-change="matrix_amount" class="flex items-center gap-2">
                    <input type="hidden" name="binding" value={binding.id} />
                    <input
                      type="range"
                      name="amount"
                      min="0"
                      max="1"
                      step="0.05"
                      value={binding.amount}
                      class="range range-xs flex-1"
                    />
                    <span class="font-mono text-xs tabular-nums w-10 text-right">
                      {:erlang.float_to_binary(binding.amount * 1.0, decimals: 2)}
                    </span>
                  </form>
                </td>
                <td>
                  <form phx-change="matrix_curve">
                    <input type="hidden" name="binding" value={binding.id} />
                    <select name="curve" class="select select-bordered select-xs">
                      <option
                        :for={curve <- Matrix.curves()}
                        value={curve}
                        selected={curve == binding.curve}
                      >
                        {curve}
                      </option>
                    </select>
                  </form>
                </td>
                <td class="text-right">
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="matrix_toggle"
                    phx-value-id={binding.id}
                  >
                    {if binding.enabled?, do: "◼", else: "▶"}
                  </button>
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="matrix_remove"
                    phx-value-id={binding.id}
                  >
                    ×
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="divider my-0 text-xs opacity-60">Quellen — was sich gerade bewegt</div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
          <.source_card label="Probes · Mittel" domain={:light} value={probe_mean(@probes)} />
          <.source_card label="Probes · Maximum" domain={:light} value={probe_max(@probes)} />
          <.source_card label="Klang · Pegel" domain={:sound} value={@features.level} />
          <.source_card label="Klang · Onsets" domain={:sound} value={@features.onset} />
        </div>

        <p class="text-[11px] opacity-60">
          Licht → Sound läuft außerdem fest über die Instrumente:
          Drone {if @drone.enabled?, do: "an", else: "aus"} ·
          Ring-Chase {if @chase.enabled?, do: "an", else: "aus"}.
          Beide lesen die Probes direkt, deshalb brauchen sie keine Zeile.
        </p>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :domain, :atom, required: true
  attr :value, :float, required: true

  defp source_card(assigns) do
    ~H"""
    <div class="bg-base-300/50 rounded-lg p-2">
      <div class="flex items-center justify-between gap-2">
        <span class="text-[11px] opacity-70">{@label}</span>
        <span class="font-mono text-[11px] tabular-nums opacity-60">
          {:erlang.float_to_binary(@value * 1.0, decimals: 2)}
        </span>
      </div>
      <div class="h-1.5 bg-base-100 rounded mt-1 overflow-hidden">
        <div
          class={["h-full", @domain == :light && "bg-warning", @domain == :sound && "bg-info"]}
          style={"width: #{round(min(max(@value, 0.0), 1.0) * 100)}%"}
        />
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

  # Source and target keys are tuples; the DOM needs a string, so they travel
  # as "kind:arg" and come back through a whitelist rather than String.to_atom.
  # Everything that turns the ring under the formula, in the order a person
  # would look for it.
  @motion_labels [
    {:roll_rate, "Rotation"},
    {:orbit_rate, "Orbit"},
    {:rot_auto, "Rotations-Sweep"},
    {:trans_auto, "Translate-Sweep"},
    {:zoom_auto, "Zoom-Sweep"},
    {:sway_auto, "Sway-Sweep"}
  ]

  defp scene_motion(config) do
    Enum.flat_map(@motion_labels, fn {key, label} ->
      case Map.get(config, key) do
        true -> [label]
        value when is_number(value) and value != 0 -> [label]
        _ -> []
      end
    end)
  end

  defp format_value(nil), do: "—"
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp format_value(value), do: to_string(value)

  # The strip is drawn from the installation's own layout, so the rows beneath
  # it have to use that geometry too: twelve panels of eight units with a gap
  # of one between them. Then a meter sits under its panel and not near it.
  @strip_panel_units 8
  @strip_gap_units 1

  defp strip_geometry do
    panels = Installation.num_panels()
    total = panels * @strip_panel_units + (panels - 1) * @strip_gap_units
    {total, @strip_panel_units, @strip_gap_units}
  end

  defp strip_aspect do
    {total, _panel, _gap} = strip_geometry()
    "aspect-ratio: #{total} / #{Installation.panel_height()}"
  end

  defp strip_gap do
    {total, _panel, gap} = strip_geometry()
    "gap: #{Float.round(gap / total * 100, 4)}%"
  end

  defp coupling_lines(chase, drone) do
    [
      {"von", "Probes 1…#{Installation.num_panels()} · Panelmitten"},
      {"nach",
       [
         chase.enabled? && "Ring-Chase (#{chase.synth}, Kanal folgt Probe)",
         drone.enabled? && "Drone (eine Stimme je Panel)"
       ]
       |> Enum.filter(& &1)
       |> case do
         [] -> "— nichts aktiv"
         targets -> Enum.join(targets, " · ")
       end},
      {"zeit", "80 ms Vorlauf · interpoliert zwischen zwei Frames"}
    ]
  end

  # Panel 1 at the top, then clockwise — the same order the strip reads in.
  defp ring_positions(panels) do
    for index <- 0..(panels - 1) do
      angle = index / panels * 2 * :math.pi() - :math.pi() / 2

      %{
        x: 100 + :math.cos(angle) * 72,
        y: 100 + :math.sin(angle) * 72,
        label_x: 100 + :math.cos(angle) * 90,
        label_y: 100 + :math.sin(angle) * 90 + 2
      }
    end
  end

  defp probe_at(probes, index), do: Enum.at(probes, index) || 0.0

  defp probe_color(value) when value >= 0, do: "#F2A33C"
  defp probe_color(_value), do: "#54D9E8"

  defp probe_mean([]), do: 0.5
  defp probe_mean(probes), do: (Enum.sum(probes) / length(probes) + 1) / 2

  defp probe_max([]), do: 0.5
  defp probe_max(probes), do: (Enum.max(probes) + 1) / 2

  defp key_to_param({kind, arg}) when is_atom(arg), do: "#{kind}:#{arg}"
  defp key_to_param({kind, arg}), do: "#{kind}:#{arg}"

  defp parse_key(nil), do: nil
  defp parse_key(""), do: nil

  defp parse_key(param) do
    known = Map.keys(Matrix.sources()) ++ Map.keys(Matrix.targets())
    Enum.find(known, &(key_to_param(&1) == param))
  end

  defp default_source, do: {:phase, 8}
  defp default_target, do: {:scene, :zoom_base}

  defp source_label(key), do: get_in(Matrix.sources(), [key, :label]) || inspect(key)
  defp target_label(key), do: get_in(Matrix.targets(), [key, :label]) || inspect(key)

  defp binding_direction(binding), do: Matrix.direction(binding.source, binding.target)

  defp direction_dots(direction) do
    case direction do
      :sound_to_light -> [{:sound, "bg-info"}, {:light, "bg-warning"}]
      :light_to_sound -> [{:light, "bg-warning"}, {:sound, "bg-info"}]
      :score -> [{:score, "bg-base-content/40"}, {:both, "bg-gradient-to-r from-warning to-info"}]
      _ -> [{:a, "bg-base-content/40"}, {:b, "bg-base-content/40"}]
    end
  end

  defp direction_label(:sound_to_light), do: "Sound → Licht"
  defp direction_label(:light_to_sound), do: "Licht → Sound"
  defp direction_label(:score), do: "Partitur → beides"
  defp direction_label(_), do: "—"

  defp filtered_bindings(bindings, :all), do: bindings

  defp filtered_bindings(bindings, filter),
    do: Enum.filter(bindings, &(binding_direction(&1) == filter))

  defp drone_state do
    safe(&Drone.state/0, %{enabled?: false, gain: 0.7, cutoff: 1800, scale: []})
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

  # The studio shows the picture that is on the wall, not merely one that
  # happens to be running: a takeover can leave an older Pixel Fun alive, and
  # showing that one would be a quiet lie about what the ring is doing.
  defp scene do
    selected = safe(&Octopus.AppManager.get_selected_app/0, nil)

    Enum.find_value(AppSupervisor.running_apps(), fn
      {PixelFun, app_id} when app_id == selected ->
        config = AppSupervisor.config(app_id)

        %{
          app_id: app_id,
          name: config[:live_scene_name] || "Pixel Fun",
          program: config[:program],
          # A rotating picture makes the chase speed up and slow down — it
          # follows the picture, and the picture is moving. Worth saying out
          # loud, because it looks like a timing fault and is not one.
          moving: scene_motion(config),
          # Shown live, so a matrix row can be watched doing its work.
          values: [
            {"Zoom", format_value(config[:zoom_base])},
            {"Sättigung", format_value(config[:saturation_percent])},
            {"Helligkeit", format_value(config[:brightness_percent])}
          ]
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
