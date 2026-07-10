defmodule Octopus.InstallationTransport do
  @moduledoc """
  Installation-level rotation queue and transport.

  Owns the single queue of `{app, mode_id}` entries, one interval, and one
  countdown. Apps publish mode catalogs via `Octopus.App.list_modes/0` and
  `mode_config/1`; this module starts/selects apps and applies modes.
  """

  use GenServer
  require Logger

  alias Octopus.{AppManager, AppSupervisor}

  # Runtime module refs avoid compile-time cycles with AppModePresets and app modules.
  @app Module.concat(["Octopus", "App"])
  @app_mode_presets Module.concat(["Octopus", "AppModePresets"])

  @topic "installation_transport"
  @default_interval_seconds 300.0

  defmodule State do
    @moduledoc false
    defstruct [
      :queue,
      :cycle_interval_seconds,
      :cycle_index,
      :cycle_timer_ref,
      :playing,
      :paused_remaining_ms,
      :next_change_at_ms,
      :live_entry,
      :rotation_paused,
      :takeover_app_id,
      :now_playing_stored_config,
      :now_playing_overrides,
      :now_playing_app_id
    ]
  end

  # -- Public API -------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def subscribe, do: Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)

  def get_state, do: GenServer.call(__MODULE__, :get_state)

  def toggle_play, do: GenServer.cast(__MODULE__, :toggle_play)
  def next, do: GenServer.cast(__MODULE__, :next)
  def prev, do: GenServer.cast(__MODULE__, :prev)

  def play_now(app, mode_id),
    do: GenServer.call(__MODULE__, {:play_now, normalize_app(app), to_string(mode_id)})

  def queue_toggle(app, mode_id) do
    GenServer.cast(__MODULE__, {:queue_toggle, normalize_app(app), to_string(mode_id)})
  end

  def queue_remove(index) when is_integer(index),
    do: GenServer.call(__MODULE__, {:queue_remove, index})

  def queue_move(index, dir) when is_integer(index),
    do: GenServer.call(__MODULE__, {:queue_move, index, dir})

  def set_queue(entries) when is_list(entries),
    do: GenServer.cast(__MODULE__, {:set_queue, Enum.map(entries, &normalize_entry/1)})

  def set_interval(seconds) when is_number(seconds),
    do: GenServer.cast(__MODULE__, {:set_interval, seconds})

  def pause_rotation_for_takeover(app_id) when is_binary(app_id),
    do: GenServer.cast(__MODULE__, {:pause_rotation_for_takeover, app_id})

  def resume_rotation_after_takeover, do: GenServer.cast(__MODULE__, :resume_rotation_after_takeover)

  @doc false
  def reset!, do: GenServer.call(__MODULE__, :reset)

  def launch_app(module) when is_atom(module),
    do: GenServer.cast(__MODULE__, {:launch_app, module})

  def set_tweakable(key, value) when is_atom(key),
    do: GenServer.call(__MODULE__, {:set_tweakable, key, value})

  def set_tweakables(changes) when is_map(changes),
    do: GenServer.call(__MODULE__, {:set_tweakables, changes})

  def discard_now_playing_overrides,
    do: GenServer.call(__MODULE__, :discard_now_playing_overrides)

  def save_now_playing_as_new(name) when is_binary(name),
    do: GenServer.call(__MODULE__, {:save_now_playing_as_new, name})

  def overwrite_now_playing_mode,
    do: GenServer.call(__MODULE__, :overwrite_now_playing_mode)

  def rename_now_playing_preset(name) when is_binary(name),
    do: GenServer.call(__MODULE__, {:rename_now_playing, name})

  def archive_now_playing_mode,
    do: GenServer.call(__MODULE__, :archive_now_playing_mode)

  # -- Callbacks --------------------------------------------------------------

  @impl true
  def init(_) do
    state = %State{
      queue: [],
      cycle_interval_seconds: @default_interval_seconds,
      cycle_index: 0,
      cycle_timer_ref: nil,
      playing: true,
      paused_remaining_ms: nil,
      next_change_at_ms: nil,
      live_entry: nil,
      rotation_paused: false,
      takeover_app_id: nil,
      now_playing_stored_config: %{},
      now_playing_overrides: %{},
      now_playing_app_id: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_state(state), state}

  def handle_call({:queue_remove, index}, _from, state) do
    new_queue = List.delete_at(state.queue, index)
    {:reply, :ok, state |> put_queue(new_queue) |> broadcast()}
  end

  def handle_call({:queue_move, index, dir}, _from, state) do
    {:reply, :ok, state |> move_queue(index, dir) |> broadcast()}
  end

  def handle_call({:set_tweakable, key, value}, _from, state) do
    {:reply, :ok, state |> apply_tweak(key, value) |> broadcast()}
  end

  def handle_call({:set_tweakables, changes}, _from, state) do
    state =
      Enum.reduce(changes, state, fn {key, value}, acc ->
        apply_tweak(acc, key, value)
      end)

    {:reply, :ok, broadcast(state)}
  end

  def handle_call(:discard_now_playing_overrides, _from, state) do
    {:reply, :ok, state |> clear_now_playing_overrides() |> apply_now_playing_config() |> broadcast()}
  end

  def handle_call({:save_now_playing_as_new, name}, _from, state) do
    case save_now_playing_as_new(state, name) do
      {:ok, new_state} -> {:reply, :ok, broadcast(new_state)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:overwrite_now_playing_mode, _from, state) do
    case overwrite_now_playing_mode(state) do
      {:ok, new_state} -> {:reply, :ok, broadcast(new_state)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:rename_now_playing, name}, _from, state) do
    case rename_now_playing_preset(state, name) do
      {:ok, new_state} -> {:reply, :ok, broadcast(new_state)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:archive_now_playing_mode, _from, state) do
    case archive_now_playing_mode(state) do
      {:ok, new_state} -> {:reply, :ok, broadcast(new_state)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reset, _from, %State{} = state) do
    state =
      %State{
        state
        | queue: [],
          cycle_index: 0,
          playing: true,
          paused_remaining_ms: nil,
          next_change_at_ms: nil,
          live_entry: nil,
          rotation_paused: false,
          takeover_app_id: nil,
          now_playing_stored_config: %{},
          now_playing_overrides: %{},
          now_playing_app_id: nil
      }
      |> cancel_timer()

    {:reply, :ok, broadcast(state)}
  end

  def handle_call({:play_now, app, mode_id}, _from, state) do
    entry = normalize_entry(%{app: app, mode_id: mode_id})

    result =
      if apply(app, :compatible?, []) do
        state =
          state
          |> apply_entry(entry)
          |> maybe_jump_queue_index(entry)
          |> maybe_takeover_off_queue_play(entry)
          |> restart_countdown()

        case state.live_entry do
          %{app: ^app, mode_id: id} when id == entry.mode_id -> {:ok, state}
          _ -> {:error, :failed, state}
        end
      else
        {:error, :incompatible, state}
      end

    {reply, state} =
      case result do
        {:ok, state} -> {:ok, state}
        {:error, reason, state} -> {{:error, reason}, state}
      end

    {:reply, reply, broadcast(state)}
  end

  @impl true
  def handle_cast(:toggle_play, %State{playing: true} = state) do
    {:noreply, state |> pause() |> broadcast()}
  end

  def handle_cast(:toggle_play, %State{playing: false} = state) do
    state =
      state
      |> clear_manual_takeover()
      |> resume()
      |> maybe_apply_live_queue_entry()

    {:noreply, broadcast(state)}
  end

  def handle_cast(:next, state) do
    {:noreply, state |> step(+1) |> broadcast()}
  end

  def handle_cast(:prev, state) do
    {:noreply, state |> step(-1) |> broadcast()}
  end

  def handle_cast({:queue_toggle, app, mode_id}, state) do
    entry = normalize_entry(%{app: app, mode_id: mode_id})
    adding? = not entry_in_queue?(state.queue, entry)

    new_queue =
      if adding? do
        state.queue ++ [entry]
      else
        List.delete(state.queue, entry)
      end

    state = state |> put_queue(new_queue)

    state =
      if adding? and is_nil(state.live_entry) and new_queue != [] do
        idx = Enum.find_index(new_queue, &(&1 == entry)) || 0

        state
        |> Map.put(:cycle_index, idx)
        |> apply_entry(entry)
        |> clear_manual_takeover()
      else
        state
      end

    {:noreply, broadcast(state)}
  end

  def handle_cast({:set_queue, entries}, state) do
    {:noreply, state |> put_queue(entries) |> broadcast()}
  end

  def handle_cast({:set_interval, seconds}, %State{} = state) do
    {:noreply, %State{state | cycle_interval_seconds: normalize_interval(seconds)} |> broadcast()}
  end

  def handle_cast({:pause_rotation_for_takeover, app_id}, %State{} = state) do
    %State{} = paused = pause(state)

    state = %State{paused | rotation_paused: true, takeover_app_id: app_id}

    {:noreply, broadcast(state)}
  end

  def handle_cast(:resume_rotation_after_takeover, %State{} = state) do
    state =
      state
      |> clear_manual_takeover()
      |> apply_queue_entry_at_cycle_index()
      |> resume()

    {:noreply, broadcast(state)}
  end

  def handle_cast({:launch_app, module}, %State{} = state) do
    cond do
      not app_rotation_eligible?(module) ->
        case AppSupervisor.start_or_select_app(module) do
          {:ok, app_id} ->
            AppManager.select_app(app_id)

            %State{} = paused = pause(state)
            state = %State{paused | rotation_paused: true, takeover_app_id: app_id}

            {:noreply, broadcast(state)}

          _ ->
            {:noreply, state}
        end

      true ->
        case AppSupervisor.start_or_select_app(module) do
          {:ok, app_id} -> AppManager.select_app(app_id)
          _ -> :ok
        end

        {:noreply, broadcast(state)}
    end
  end

  @impl true
  def handle_info(:cycle_tick, state) do
    if state.rotation_paused or length(state.queue) < 2 do
      {:noreply, state}
    else
      next_index = rem(state.cycle_index + 1, length(state.queue))
      entry = Enum.at(state.queue, next_index)

      state =
        state
        |> Map.put(:cycle_index, next_index)
        |> apply_entry(entry)
        |> restart_countdown()

      {:noreply, broadcast(state)}
    end
  end

  # -- Queue / transport helpers ----------------------------------------------

  defp put_queue(%State{} = state, queue) do
    index =
      case state.live_entry do
        live when is_map(live) ->
          case Enum.find_index(queue, &(&1 == live)) do
            nil -> clamp_index(state.cycle_index, queue)
            idx -> idx
          end

        _ ->
          clamp_index(state.cycle_index, queue)
      end

    %State{state | queue: queue, cycle_index: index} |> schedule_change()
  end

  defp move_queue(%State{queue: queue} = state, index, dir) do
    swap = if dir == "up", do: index - 1, else: index + 1

    if swap >= 0 and swap < length(queue) do
      a = Enum.at(queue, index)
      b = Enum.at(queue, swap)

      new_queue =
        queue
        |> List.replace_at(index, b)
        |> List.replace_at(swap, a)

      put_queue(state, new_queue)
    else
      state
    end
  end

  defp maybe_jump_queue_index(%State{} = state, entry) do
    case Enum.find_index(state.queue, &(&1 == entry)) do
      nil -> state
      index -> %State{state | cycle_index: index}
    end
  end

  # Off-queue Play now pauses auto-rotation (without flipping playing=false).
  defp maybe_takeover_off_queue_play(%State{} = state, entry) do
    cond do
      entry_in_queue?(state.queue, entry) ->
        clear_manual_takeover(state)

      is_nil(state.now_playing_app_id) ->
        state

      true ->
        %State{state | rotation_paused: true, takeover_app_id: state.now_playing_app_id}
    end
  end

  defp clear_manual_takeover(%State{} = state) do
    %State{state | rotation_paused: false, takeover_app_id: nil}
  end

  defp maybe_apply_live_queue_entry(%State{live_entry: nil, queue: queue} = state)
       when queue != [] do
    entry = Enum.at(queue, state.cycle_index)
    apply_entry(state, entry)
  end

  defp maybe_apply_live_queue_entry(%State{} = state), do: state

  defp apply_queue_entry_at_cycle_index(%State{queue: []} = state), do: state

  defp apply_queue_entry_at_cycle_index(%State{} = state) do
    entry = Enum.at(state.queue, state.cycle_index)
    apply_entry(state, entry)
  end

  defp step(%State{queue: queue} = state, _dir) when length(queue) < 2, do: state

  defp step(%State{queue: queue, cycle_index: index} = state, dir) do
    next_index = Integer.mod(index + dir, length(queue))
    entry = Enum.at(queue, next_index)

    state
    |> Map.put(:cycle_index, next_index)
    |> apply_entry(entry)
    |> restart_countdown()
  end

  defp apply_entry(%State{} = state, %{app: app, mode_id: mode_id} = entry) do
    mode_config = app_mode_config(app, mode_id)

    app_id =
      case AppSupervisor.find_running_app(app) do
        {:ok, id} ->
          if map_size(mode_config) > 0, do: AppSupervisor.update_config(id, mode_config)
          id

        :not_found ->
          stored = stored_config_for(app, mode_id)

          case AppSupervisor.start_app(app, config: stored) do
            {:ok, id} ->
              id

            {:error, reason} ->
              Logger.warning("play_now start_app #{inspect(app)} failed: #{inspect(reason)}")
              nil
          end
      end

    if app_id do
      stored = stored_config_for(app, mode_id, app_id)

      AppManager.select_app(app_id)
      app_apply_mode(app_id, app, mode_id)

      %State{
        state
        | live_entry: entry,
          now_playing_stored_config: stored,
          now_playing_overrides: %{},
          now_playing_app_id: app_id
      }
    else
      state
    end
  end

  defp apply_tweak(%State{live_entry: nil} = state, _key, _value), do: state

  defp apply_tweak(%State{} = state, key, value) do
    key = normalize_tweak_key(key)
    stored = state.now_playing_stored_config
    parsed = parse_tweak_value(state, key, value)

    overrides =
      if value_eq?(parsed, Map.get(stored, key)) do
        Map.delete(state.now_playing_overrides, key)
      else
        Map.put(state.now_playing_overrides, key, parsed)
      end

    state = %State{state | now_playing_overrides: overrides}
    apply_now_playing_config(state)
  end

  defp apply_now_playing_config(%State{live_entry: nil} = state), do: state

  defp apply_now_playing_config(%State{} = state) do
    effective = effective_config(state)

    case resolve_now_playing_app_id(state) do
      {nil, state} ->
        state

      {app_id, state} ->
        current = config_map(app_id)
        AppSupervisor.update_config(app_id, Map.merge(current, effective))
        state
    end
  end

  defp resolve_now_playing_app_id(%State{} = state) do
    cond do
      is_binary(state.now_playing_app_id) and app_running?(state.now_playing_app_id) ->
        {state.now_playing_app_id, state}

      match?(%{app: _}, state.live_entry) ->
        case AppSupervisor.find_running_app(state.live_entry.app) do
          {:ok, app_id} ->
            {app_id, %State{state | now_playing_app_id: app_id}}

          :not_found ->
            case start_live_app(state) do
              nil -> {nil, %State{state | now_playing_app_id: nil}}
              app_id -> {app_id, %State{state | now_playing_app_id: app_id}}
            end
        end

      true ->
        {nil, %State{state | now_playing_app_id: nil}}
    end
  end

  defp start_live_app(%State{live_entry: %{app: app, mode_id: mode_id}} = state) do
    config = effective_config(state)

    case AppSupervisor.start_app(app, config: config) do
      {:ok, app_id} ->
        AppManager.select_app(app_id)
        app_apply_mode(app_id, app, mode_id)
        app_id

      {:error, reason} ->
        Logger.warning("now_playing restart #{inspect(app)} failed: #{inspect(reason)}")
        nil
    end
  end

  defp app_running?(app_id) when is_binary(app_id) do
    case AppSupervisor.config(app_id) do
      config when is_map(config) -> true
      _ -> false
    end
  end

  defp config_map(app_id) when is_binary(app_id) do
    case AppSupervisor.config(app_id) do
      config when is_map(config) -> config
      _ -> %{}
    end
  end

  defp clear_now_playing_overrides(%State{} = state) do
    %State{state | now_playing_overrides: %{}}
  end

  defp save_now_playing_as_new(%State{live_entry: nil}, _name), do: {:error, :nothing_playing}

  defp save_now_playing_as_new(%State{live_entry: %{app: app}} = state, name) do
    if preset_persistable?(app) do
      %{app: app, mode_id: mode_id} = state.live_entry
      effective = effective_config(state)
      attrs = preset_attrs_from_effective(app, mode_id, effective)

      case preset_create(app, name, attrs.config, accent_color: attrs[:accent_color]) do
        {:ok, _preset} ->
          {:ok, clear_now_playing_overrides(state)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unsupported}
    end
  end

  defp overwrite_now_playing_mode(%State{live_entry: %{app: app, mode_id: mode_id}} = state) do
    if preset_persistable?(app) do
      effective = effective_config(state)
      attrs = preset_attrs_from_effective(app, mode_id, effective)

      case preset_update(app, mode_id, %{config: attrs.config}) do
        {:ok, preset} ->
          stored = preset.config
          cleared = clear_now_playing_overrides(state)
          new_state = %State{cleared | now_playing_stored_config: stored} |> apply_now_playing_config()
          {:ok, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unsupported}
    end
  end

  defp rename_now_playing_preset(%State{live_entry: %{app: app, mode_id: mode_id}} = state, name) do
    if preset_persistable?(app) do
      case preset_rename(app, mode_id, name) do
        {:ok, _preset} -> {:ok, state}
        error -> error
      end
    else
      {:error, :unsupported}
    end
  end

  defp archive_now_playing_mode(%State{live_entry: %{app: app, mode_id: mode_id}} = state) do
    if preset_persistable?(app) do
      case preset_archive(app, mode_id) do
        :ok ->
          new_queue = preset_filter_queue(state.queue, app, mode_id)
          {:ok, put_queue(state, new_queue)}

        error ->
          error
      end
    else
      {:error, :unsupported}
    end
  end

  defp effective_config(%State{} = state) do
    Map.merge(state.now_playing_stored_config, state.now_playing_overrides)
  end

  defp stored_config_for(app, mode_id, app_id \\ nil) do
    mode_config = app_mode_config(app, mode_id)
    defaults = tweakable_defaults(app, mode_id)
    base = Map.merge(defaults, mode_config)

    case app_id || running_app_id(app) do
      nil ->
        base

      id ->
        current = config_map(id)
        Map.merge(base, Map.take(current, tweakable_keys(app, mode_id)))
    end
  end

  defp running_app_id(app) do
    case AppSupervisor.find_running_app(app) do
      {:ok, id} -> id
      :not_found -> nil
    end
  end

  defp tweakable_keys(app, mode_id) do
    app
    |> app_mode_tweakables(mode_id)
    |> Enum.map(& &1.key)
  end

  defp tweakable_defaults(app, mode_id) do
    app
    |> app_mode_tweakables(mode_id)
    |> Enum.map(fn %{key: key, default: default} -> {key, default} end)
    |> Map.new()
  end

  defp build_now_playing(%State{live_entry: nil}), do: nil

  defp build_now_playing(%State{} = state) do
    %{app: app, mode_id: mode_id} = state.live_entry
    stored = state.now_playing_stored_config
    overrides = state.now_playing_overrides
    effective = effective_config(state)
    tweakables = app_mode_tweakables(app, mode_id)

    preset = preset_get(app, mode_id)

    %{
      app: app,
      mode_id: mode_id,
      app_id: state.now_playing_app_id,
      preset_name: preset && preset.name,
      stored: stored,
      overrides: overrides,
      effective: effective,
      dirty: now_playing_dirty?(stored, overrides, tweakables),
      tweakables: tweakables,
      meta: app_now_playing_meta(app, effective),
      persistable: preset_persistable?(app),
      overwriteable: preset_persistable?(app) and not is_nil(preset),
      deletable: preset_persistable?(app) and not is_nil(preset),
      renamable: preset_persistable?(app) and not is_nil(preset),
      preset_label: preset_label(app)
    }
  end

  defp now_playing_dirty?(stored, overrides, tweakables) do
    map_size(overrides) > 0 and
      Enum.any?(tweakables, fn %{key: key} ->
        Map.has_key?(overrides, key) and not value_eq?(Map.get(stored, key), Map.get(overrides, key))
      end)
  end

  defp parse_tweak_value(%State{live_entry: %{app: app, mode_id: mode_id}}, key, value) do
    spec =
      app
      |> app_mode_tweakables(mode_id)
      |> Enum.find(&(&1.key == key))

    case spec do
      %{type: :slider, step: step} = s when is_integer(step) and step >= 1 ->
        parse_number(value)
        |> clamp_number(s.min, s.max)
        |> maybe_round_step(step)
        |> trunc()

      %{type: :slider} = s ->
        parse_number(value) |> clamp_number(s.min, s.max) |> maybe_round_step(s.step)

      %{type: :toggle} ->
        value in [true, "true", "1", 1]

      %{type: :choice, options: options} ->
        parse_choice(value, options)

      %{type: :color} ->
        normalize_hex_color(value)

      %{type: :formula} ->
        value |> to_string() |> String.trim()

      _ ->
        value
    end
  end

  defp parse_choice(value, options) when is_binary(value) do
    case Integer.parse(value) do
      {index, _} ->
        options |> Enum.at(index) |> elem_or_key(0)

      :error ->
        String.to_existing_atom(value)
    end
  rescue
    ArgumentError -> value
  end

  defp parse_choice(value, _options) when is_atom(value), do: value
  defp parse_choice(value, _options), do: value

  defp elem_or_key({key, _label}, _), do: key
  defp elem_or_key(key, _), do: key

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_number(value) when is_integer(value), do: value * 1.0
  defp parse_number(value) when is_float(value), do: value
  defp parse_number(value) when is_boolean(value), do: value
  defp parse_number(_), do: 0

  defp clamp_number(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end

  defp clamp_number(value, _min, _max), do: value

  defp maybe_round_step(value, step) when is_number(value) and is_number(step) and step >= 1 do
    round(value / step) * step
  end

  defp maybe_round_step(value, step) when is_number(value) and is_number(step) do
    Float.round(value / step) * step
  end

  defp maybe_round_step(value, _), do: value

  defp normalize_tweak_key(key) when is_atom(key), do: key

  defp normalize_tweak_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  end

  defp normalize_hex_color(value) when is_binary(value) do
    value =
      if String.starts_with?(value, "#") do
        value
      else
        "#" <> value
      end

    case value do
      "#" <> hex when byte_size(hex) == 6 -> "#" <> String.downcase(hex)
      _ -> "#ffffff"
    end
  end

  defp normalize_hex_color(_), do: "#ffffff"

  defp value_eq?(a, b) when is_number(a) and is_number(b), do: abs(a - b) < 0.001
  defp value_eq?(a, b), do: a == b

  defp schedule_change(%State{rotation_paused: true} = state), do: cancel_timer(state)
  defp schedule_change(%State{playing: false} = state), do: cancel_timer(state)

  defp schedule_change(%State{queue: queue} = state) when length(queue) < 2 do
    %State{cancel_timer(state) | next_change_at_ms: nil}
  end

  defp schedule_change(%State{next_change_at_ms: deadline} = state)
       when is_integer(deadline) and deadline > 0 do
    remaining = max(deadline - now_ms(), 1)
    arm_timer(state, remaining, deadline)
  end

  defp schedule_change(%State{} = state), do: restart_countdown(state)

  defp restart_countdown(%State{queue: queue} = state) when length(queue) < 2 do
    %State{cancel_timer(state) | next_change_at_ms: nil}
  end

  defp restart_countdown(%State{playing: false} = state) do
    %State{cancel_timer(state) | next_change_at_ms: nil}
  end

  defp restart_countdown(%State{rotation_paused: true} = state) do
    %State{cancel_timer(state) | next_change_at_ms: nil}
  end

  defp restart_countdown(%State{} = state) do
    ms = interval_ms(state)
    arm_timer(state, ms, now_ms() + ms)
  end

  defp arm_timer(%State{} = state, remaining_ms, deadline_ms) do
    state = cancel_timer(state)
    ref = Process.send_after(self(), :cycle_tick, remaining_ms)
    %State{state | cycle_timer_ref: ref, next_change_at_ms: deadline_ms, paused_remaining_ms: nil}
  end

  defp cancel_timer(%State{cycle_timer_ref: nil} = state), do: state

  defp cancel_timer(%State{cycle_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %State{state | cycle_timer_ref: nil}
  end

  defp pause(%State{} = state) do
    remaining =
      case state.next_change_at_ms do
        deadline when is_integer(deadline) -> max(deadline - now_ms(), 0)
        _ -> nil
      end

    %State{
      cancel_timer(state)
      | playing: false,
        paused_remaining_ms: remaining,
        next_change_at_ms: nil
    }
  end

  defp resume(%State{queue: queue} = state) when length(queue) < 2 do
    %State{state | playing: true, paused_remaining_ms: nil, next_change_at_ms: nil}
  end

  defp resume(%State{paused_remaining_ms: remaining} = state) when is_integer(remaining) do
    remaining = max(remaining, 1)
    arm_timer(%State{state | playing: true}, remaining, now_ms() + remaining)
  end

  defp resume(%State{} = state) do
    restart_countdown(%State{state | playing: true})
  end

  defp broadcast(%State{} = state) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:installation_transport, public_state(state)})
    state
  end

  defp public_state(%State{} = state) do
    live = enrich_entry(state.live_entry)

    %{
      queue: Enum.map(state.queue, &enrich_entry/1),
      cycle_interval_seconds: state.cycle_interval_seconds,
      cycle_index: state.cycle_index,
      playing: state.playing,
      paused_remaining_ms: state.paused_remaining_ms,
      next_change_at_ms: state.next_change_at_ms,
      live: live,
      rotation_paused: state.rotation_paused,
      takeover_app_id: state.takeover_app_id,
      takeover_app_name: takeover_name(state.takeover_app_id),
      now_playing: build_now_playing(state)
    }
  end

  defp enrich_entry(nil), do: nil

  defp enrich_entry(%{app: app, mode_id: mode_id} = entry) do
    mode = find_mode(app, mode_id)

    Map.merge(entry, %{
      app_name: app_name(app),
      mode_name: mode && mode.name || mode_id,
      accent_color: mode && mode.accent_color || "#6d7cff",
      summary: mode && Map.get(mode, :summary) || "",
      builtin: mode && Map.get(mode, :builtin, true)
    })
  end

  defp find_mode(app, mode_id) do
    normalized = preset_normalize_mode_id(app, mode_id)

    case preset_get(app, normalized) do
      nil ->
        Enum.find(app_list_modes(app), fn mode ->
          preset_normalize_mode_id(app, mode.id) == normalized
        end)

      preset ->
        %{
          id: preset.id,
          name: preset.name,
          accent_color: preset.accent_color,
          summary: preset_summary(app, preset),
          builtin: preset.builtin
        }
    end
  end

  defp takeover_name(nil), do: nil

  defp takeover_name(app_id) do
    case AppSupervisor.lookup_app(app_id) do
      {_pid, module} -> app_name(module)
      _ -> nil
    end
  end

  defp entry_in_queue?(queue, entry), do: entry in queue

  defp normalize_entry(%{app: app, mode_id: id}) do
    app = normalize_app(app)
    id = to_string(id)

    mode_id =
      if preset_persistable?(app) do
        preset_normalize_mode_id(app, id)
      else
        id
      end

    %{app: app, mode_id: mode_id}
  end

  defp normalize_app(app) when is_atom(app) do
    if Code.ensure_loaded?(app) and function_exported?(app, :list_modes, 0) do
      app
    else
      Module.concat(Octopus.Apps, app)
    end
  end

  defp normalize_app(app) when is_binary(app), do: parse_app_module_string(app)

  defp parse_app_module_string(str) when is_binary(str) do
    cond do
      String.starts_with?(str, "Elixir.") ->
        String.to_existing_atom(str)

      String.contains?(str, ".") ->
        str |> String.split(".") |> Enum.map(&String.to_existing_atom/1) |> Module.concat()

      true ->
        Module.concat(Octopus.Apps, String.to_existing_atom(str))
    end
  end

  defp normalize_interval(seconds) when is_number(seconds), do: seconds * 1.0 |> max(1.0)
  defp normalize_interval(_), do: @default_interval_seconds

  defp interval_ms(%State{cycle_interval_seconds: seconds}) do
    seconds |> normalize_interval() |> Kernel.*(1000) |> trunc() |> max(1)
  end

  defp clamp_index(_index, []), do: 0
  defp clamp_index(index, queue), do: index |> max(0) |> min(length(queue) - 1)

  defp now_ms, do: System.os_time(:millisecond)

  defp app_rotation_eligible?(module), do: apply(@app, :rotation_eligible?, [module])
  defp app_mode_config(app, mode_id), do: apply(@app, :mode_config, [app, mode_id])
  defp app_apply_mode(app_id, app, mode_id), do: apply(@app, :apply_mode, [app_id, app, mode_id])
  defp app_mode_tweakables(app, mode_id), do: apply(@app, :mode_tweakables, [app, mode_id])
  defp app_now_playing_meta(app, config), do: apply(@app, :now_playing_meta, [app, config])
  defp app_name(app), do: apply(@app, :name, [app])
  defp app_list_modes(app), do: apply(@app, :list_modes, [app])

  defp preset_persistable?(app), do: apply(@app_mode_presets, :persistable?, [app])
  defp preset_attrs_from_effective(app, mode_id, effective),
    do: apply(@app_mode_presets, :attrs_from_effective, [app, mode_id, effective])

  defp preset_create(app, name, config, opts),
    do: apply(@app_mode_presets, :create, [app, name, config, opts])

  defp preset_update(app, mode_id, attrs),
    do: apply(@app_mode_presets, :update, [app, mode_id, attrs])

  defp preset_rename(app, mode_id, name),
    do: apply(@app_mode_presets, :rename, [app, mode_id, name])

  defp preset_archive(app, mode_id), do: apply(@app_mode_presets, :archive, [app, mode_id])

  defp preset_filter_queue(queue, app, mode_id),
    do: apply(@app_mode_presets, :filter_queue, [queue, app, mode_id])

  defp preset_get(app, mode_id), do: apply(@app_mode_presets, :get, [app, mode_id])
  defp preset_label(app), do: apply(@app_mode_presets, :preset_label, [app])

  defp preset_normalize_mode_id(app, mode_id),
    do: apply(@app_mode_presets, :normalize_mode_id, [app, mode_id])

  defp preset_summary(app, preset), do: apply(@app_mode_presets, :summary, [app, preset])
end
