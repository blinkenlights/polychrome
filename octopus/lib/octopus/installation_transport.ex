defmodule Octopus.InstallationTransport do
  @moduledoc """
  Installation-level rotation queue and transport.

  Owns the single queue of `{app, mode_id}` entries, one interval, and one
  countdown. Apps publish mode catalogs via `Octopus.App.list_modes/0` and
  `mode_config/1`; this module starts/selects apps and applies modes.
  """

  use GenServer
  require Logger

  alias Octopus.{AppManager, AppSupervisor, Mixer}
  alias Octopus.InstallationTransport.PersistedState

  # Runtime module refs avoid compile-time cycles with AppModePresets and app modules.
  @app Module.concat(["Octopus", "App"])
  @app_mode_presets Module.concat(["Octopus", "AppModePresets"])

  @topic "installation_transport"
  @default_interval_seconds 300.0
  @default_transition_duration_seconds 1.0

  defmodule State do
    @moduledoc false
    defstruct [
      :queue,
      :cycle_interval_seconds,
      :transition_duration_seconds,
      :cycle_index,
      :cycle_timer_ref,
      :playing,
      :paused_remaining_ms,
      :next_change_at_ms,
      :live_entry,
      :pending_entry,
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

  def queue_add_all(app) when is_atom(app),
    do: GenServer.cast(__MODULE__, {:queue_add_all, normalize_app(app)})

  def queue_remove(index) when is_integer(index),
    do: GenServer.call(__MODULE__, {:queue_remove, index})

  def queue_move(index, dir) when is_integer(index),
    do: GenServer.call(__MODULE__, {:queue_move, index, dir})

  def queue_set_mask(index, mask) when is_integer(index) do
    GenServer.call(__MODULE__, {:queue_set_mask, index, normalize_mask(mask)})
  end

  def set_queue(entries) when is_list(entries),
    do: GenServer.cast(__MODULE__, {:set_queue, Enum.map(entries, &normalize_entry/1)})

  def set_interval(seconds) when is_number(seconds),
    do: GenServer.cast(__MODULE__, {:set_interval, seconds})

  def set_transition_duration(seconds) when is_number(seconds),
    do: GenServer.cast(__MODULE__, {:set_transition_duration, seconds})

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

  # -- Callbacks --------------------------------------------------------------

  @impl true
  def init(_) do
    persisted = PersistedState.load()
    queue = load_queue(persisted)

    state = %State{
      queue: queue,
      cycle_interval_seconds: (persisted && persisted.cycle_interval_seconds) || @default_interval_seconds,
      transition_duration_seconds: (persisted && persisted.transition_duration_seconds) || @default_transition_duration_seconds,
      cycle_index: clamp_index((persisted && persisted.cycle_index) || 0, queue),
      cycle_timer_ref: nil,
      playing: if(persisted, do: persisted.playing, else: true),
      paused_remaining_ms: nil,
      next_change_at_ms: nil,
      live_entry: nil,
      pending_entry: nil,
      rotation_paused: false,
      takeover_app_id: nil,
      now_playing_stored_config: %{},
      now_playing_overrides: %{},
      now_playing_app_id: nil
    }

    {:ok, state, {:continue, :restore_playback}}
  end

  @impl true
  def handle_continue(:restore_playback, %State{queue: []} = state) do
    AppSupervisor.subscribe()
    {:noreply, broadcast(state)}
  end

  def handle_continue(:restore_playback, %State{} = state) do
    AppSupervisor.subscribe()

    state =
      state
      |> clear_manual_takeover()
      |> Map.put(:playing, true)
      |> restore_queue_playback()

    {:noreply, state |> broadcast() |> persist_queue_state()}
  end

  @impl true
  def terminate(reason, %State{} = state) do
    Logger.info("InstallationTransport terminating: #{inspect(reason)}")
    persist_queue_state_sync(state)
    :ok
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_state(state), state}

  def handle_call({:queue_remove, index}, _from, state) do
    new_queue = List.delete_at(state.queue, index)
    {:reply, :ok, state |> put_queue(new_queue) |> broadcast() |> persist_queue_state()}
  end

  def handle_call({:queue_move, index, dir}, _from, state) do
    {:reply, :ok, state |> move_queue(index, dir) |> broadcast() |> persist_queue_state()}
  end

  def handle_call({:queue_set_mask, index, mask}, _from, state) do
    case Enum.at(state.queue, index) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        updated = Map.put(entry, :mask, mask)
        new_queue = List.replace_at(state.queue, index, updated)
        state = state |> put_queue(new_queue)

        state =
          if state.live_entry && entries_match_front?(state.live_entry, entry) do
            case apply_entry(state, updated) do
              {:ok, s} -> s
              {:error, _, s} -> s
            end
          else
            state
          end

        {:reply, :ok, state |> broadcast() |> persist_queue_state()}
    end
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
    state =
      state
      |> clear_now_playing_overrides()
      |> reapply_now_playing_mode()
      |> apply_now_playing_config()
      |> broadcast()

    {:reply, :ok, state}
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
          now_playing_app_id: nil,
          pending_entry: nil
      }
      |> cancel_timer()

    AppSupervisor.stop_mask_app()

    {:reply, :ok, state |> broadcast() |> persist_queue_state()}
  end

  def handle_call({:play_now, app, mode_id}, _from, state) do
    base_entry = normalize_entry(%{app: app, mode_id: mode_id})

    entry =
      case find_queue_index(state.queue, base_entry) do
        nil -> base_entry
        index -> Enum.at(state.queue, index)
      end

    result =
      if apply(app, :compatible?, []) do
        state =
          state
          |> apply_entry_or_keep(entry)
          |> maybe_jump_queue_index(entry)
          |> maybe_takeover_off_queue_play(entry)
          |> restart_countdown()

        cond do
          state.pending_entry == entry ->
            {:ok, state}

          true ->
            case state.live_entry do
              %{app: ^app, mode_id: live_mode} when live_mode == entry.mode_id ->
                {:ok, state}

              _ ->
                {:error, :failed, state}
            end
        end
      else
        {:error, :incompatible, state}
      end

    {reply, state} =
      case result do
        {:ok, state} -> {:ok, state}
        {:error, reason, state} -> {{:error, reason}, state}
      end

    {:reply, reply, state |> broadcast() |> persist_queue_state()}
  end

  @impl true
  def handle_cast(:toggle_play, %State{playing: true} = state) do
    {:noreply, state |> pause() |> broadcast() |> persist_queue_state()}
  end

  def handle_cast(:toggle_play, %State{playing: false} = state) do
    state =
      state
      |> clear_manual_takeover()
      |> resume()
      |> maybe_apply_live_queue_entry()

    {:noreply, state |> broadcast() |> persist_queue_state()}
  end

  def handle_cast(:next, state) do
    {:noreply, state |> step(+1) |> broadcast() |> persist_queue_state()}
  end

  def handle_cast(:prev, state) do
    {:noreply, state |> step(-1) |> broadcast() |> persist_queue_state()}
  end

  def handle_cast({:queue_toggle, app, mode_id}, state) do
    entry = normalize_entry(%{app: app, mode_id: mode_id})
    adding? = not entry_in_queue?(state.queue, entry)

    new_queue =
      if adding? do
        state.queue ++ [entry]
      else
        reject_queue_entry(state.queue, entry)
      end

    state = state |> put_queue(new_queue)

    state =
      if adding? and is_nil(state.live_entry) and new_queue != [] do
        idx = Enum.find_index(new_queue, &(&1 == entry)) || 0

        state
        |> Map.put(:cycle_index, idx)
        |> apply_entry_or_keep(entry)
        |> clear_manual_takeover()
      else
        state
      end

    {:noreply, state |> broadcast() |> persist_queue_state()}
  end

  def handle_cast({:queue_add_all, app}, state) do
    entries =
      @app.list_modes(app)
      |> Enum.map(&normalize_entry(%{app: app, mode_id: &1.id}))

    new_entries = Enum.reject(entries, &entry_in_queue?(state.queue, &1))

    if new_entries == [] do
      {:noreply, state}
    else
      empty_queue? = state.queue == []
      new_queue = state.queue ++ new_entries
      state = state |> put_queue(new_queue)
      first_entry = hd(new_entries)

      state =
        if empty_queue? and is_nil(state.live_entry) do
          idx = Enum.find_index(new_queue, &(&1 == first_entry)) || 0

          state
          |> Map.put(:cycle_index, idx)
          |> apply_entry_or_keep(first_entry)
          |> clear_manual_takeover()
        else
          state
        end

      {:noreply, state |> broadcast() |> persist_queue_state()}
    end
  end

  def handle_cast({:set_queue, entries}, state) do
    {:noreply, state |> put_queue(entries) |> broadcast() |> persist_queue_state()}
  end

  def handle_cast({:set_interval, seconds}, %State{} = state) do
    {:noreply, %State{state | cycle_interval_seconds: normalize_interval(seconds)} |> broadcast() |> persist_queue_state()}
  end

  def handle_cast({:set_transition_duration, seconds}, %State{} = state) do
    {:noreply,
     %State{state | transition_duration_seconds: normalize_transition_duration(seconds)}
     |> broadcast()
     |> persist_queue_state()}
  end

  def handle_cast(:commit_pending_entry, %State{} = state) do
    {:noreply, state |> commit_pending_entry() |> broadcast()}
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
      |> resume_after_takeover()
      |> resume()

    {:noreply, broadcast(state)}
  end

  def handle_cast({:launch_app, module}, %State{} = state) do
    case AppSupervisor.start_or_select_app(module) do
      {:ok, app_id} ->
        AppManager.select_app(app_id)
        AppSupervisor.stop_mask_app()

        %State{} = paused = pause(state)

        state = %State{
          paused
          | rotation_paused: true,
            takeover_app_id: app_id,
            live_entry: nil,
            pending_entry: nil,
            now_playing_app_id: nil,
            now_playing_stored_config: %{},
            now_playing_overrides: %{}
        }

        {:noreply, broadcast(state)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:apps, {:stopped, app_id}}, %State{} = state) do
    if live_playback_interrupted?(state, app_id) do
      {:noreply, state |> restart_live_from_queue() |> broadcast() |> persist_queue_state()}
    else
      {:noreply, state}
    end
  end

  def handle_info({:apps, _event}, %State{} = state), do: {:noreply, state}

  def handle_info(:cycle_tick, state) do
    if state.rotation_paused or state.queue == [] do
      {:noreply, state}
    else
      next_index = rem(state.cycle_index + 1, length(state.queue))
      entry = Enum.at(state.queue, next_index)

      state =
        state
        |> Map.put(:cycle_index, next_index)
        |> apply_entry_or_keep(entry)
        |> restart_countdown()

      {:noreply, state |> broadcast() |> persist_queue_state()}
    end
  end

  defp put_queue(%State{} = state, queue) do
    index =
      case state.live_entry do
        live when is_map(live) ->
          case find_queue_index(queue, live) do
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
    case find_queue_index(state.queue, entry) do
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
    apply_entry_or_keep(state, entry)
  end

  defp maybe_apply_live_queue_entry(%State{} = state), do: state

  defp apply_queue_entry_at_cycle_index(%State{} = state) do
    entry = Enum.at(state.queue, state.cycle_index)
    apply_entry_or_keep(state, entry)
  end

  defp restart_live_from_queue(%State{} = state) do
    entry = Enum.at(state.queue, state.cycle_index)

    %State{state | now_playing_app_id: nil, pending_entry: entry}
    |> commit_pending_entry()
    |> restart_countdown()
  end

  defp live_playback_interrupted?(%State{} = state, stopped_app_id) do
    state.playing and
      not state.rotation_paused and
      state.live_entry != nil and
      state.queue != [] and
      (state.now_playing_app_id == stopped_app_id or not live_app_running?(state))
  end

  defp live_app_running?(%State{now_playing_app_id: app_id}) when is_binary(app_id) do
    app_running?(app_id)
  end

  defp live_app_running?(%State{live_entry: %{app: app}}) do
    AppSupervisor.find_running_app(app) != :not_found
  end

  defp live_app_running?(_), do: false

  defp resume_after_takeover(%State{queue: []} = state) do
    state
    |> deselect_now_playing_app()
    |> clear_live_playback()
  end

  defp resume_after_takeover(%State{} = state), do: apply_queue_entry_at_cycle_index(state)

  defp deselect_now_playing_app(%State{now_playing_app_id: app_id} = state) when is_binary(app_id) do
    AppManager.select_app(nil)
    state
  end

  defp deselect_now_playing_app(%State{} = state), do: state

  defp clear_live_playback(%State{} = state) do
    state = cancel_timer(state)
    AppSupervisor.stop_mask_app()

    %State{
      state
      | live_entry: nil,
        now_playing_app_id: nil,
        now_playing_stored_config: %{},
        now_playing_overrides: %{},
        next_change_at_ms: nil,
        paused_remaining_ms: nil
    }
  end

  defp step(%State{queue: []} = state, _dir), do: state

  defp step(%State{queue: queue, cycle_index: index} = state, dir) do
    next_index = Integer.mod(index + dir, length(queue))
    entry = Enum.at(queue, next_index)

    state
    |> Map.put(:cycle_index, next_index)
    |> apply_entry_or_keep(entry)
    |> restart_countdown()
  end

  defp apply_entry_or_keep(%State{} = state, entry) do
    state = %State{state | pending_entry: entry}
    duration_ms = transition_duration_ms(state)

    if duration_ms > 0 do
      Mixer.run_transition(duration_ms, fn ->
        GenServer.cast(__MODULE__, :commit_pending_entry)
      end)

      state
    else
      commit_pending_entry(state)
    end
  end

  defp commit_pending_entry(%State{pending_entry: nil} = state), do: state

  defp commit_pending_entry(%State{} = state) do
    entry = state.pending_entry
    state = %State{state | pending_entry: nil}

    case apply_entry(state, entry) do
      {:ok, state} ->
        state

      {:error, reason, state} ->
        Logger.warning("apply_entry failed: #{inspect(reason)}")
        state
    end
  end

  defp apply_entry(%State{} = state, %{app: app, mode_id: mode_id} = entry) do
    mode_config = app_mode_config(app, mode_id)

    app_id =
      case AppSupervisor.find_running_app(app) do
        {:ok, id} ->
          if map_size(mode_config) > 0 do
            case safe_update_config(id, mode_config) do
              :ok -> id
              {:error, reason} -> {:error, reason}
            end
          else
            id
          end

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

    case app_id do
      {:error, reason} ->
        {:error, reason, state}

      app_id when is_binary(app_id) ->
        stored = stored_config_for(app, mode_id, app_id)

        AppManager.select_app(app_id)
        app_apply_mode(app_id, app, mode_id)
        apply_entry_mask(entry)

        {:ok,
         %State{
           state
           | live_entry: entry,
             now_playing_stored_config: stored,
             now_playing_overrides: %{},
             now_playing_app_id: app_id
         }}

      _ ->
        apply_entry_mask(entry)
        {:ok, state}
    end
  end

  defp apply_entry_mask(%{mask: %{app: app, mode_id: mode_id}}) do
    config = stored_config_for(app, mode_id)

    case AppSupervisor.start_as_mask_app(app, config: config) do
      {:ok, _id} ->
        :ok

      {:error, reason} ->
        Logger.warning("apply_entry_mask #{inspect(app)} failed: #{inspect(reason)}")
        AppSupervisor.stop_mask_app()
    end
  end

  defp apply_entry_mask(_entry) do
    AppSupervisor.stop_mask_app()
  end

  defp safe_update_config(app_id, config) do
    try do
      :ok = AppSupervisor.update_config(app_id, config)
      :ok
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, reason}
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

  # Discard is a hard reset: re-apply the live mode so the app fully reinitializes
  # to the stored preset (e.g. PixelFun3D resets integrated yaw/roll/zoom + wanderers
  # via reset_orientation_from_scene), not just the config overrides.
  defp reapply_now_playing_mode(%State{live_entry: %{app: app, mode_id: mode_id}} = state) do
    case resolve_now_playing_app_id(state) do
      {app_id, state} when is_binary(app_id) ->
        app_apply_mode(app_id, app, mode_id)
        state

      {_, state} ->
        state
    end
  end

  defp reapply_now_playing_mode(%State{} = state), do: state

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

  defp effective_config(%State{live_entry: %{app: app, mode_id: mode_id}} = state) do
    state.now_playing_stored_config
    |> Map.merge(state.now_playing_overrides)
    |> fill_missing_tweakables(app, mode_id, state.now_playing_app_id)
  end

  defp effective_config(%State{} = state) do
    Map.merge(state.now_playing_stored_config, state.now_playing_overrides)
  end

  defp fill_missing_tweakables(config, app, mode_id, app_id) when is_map(config) do
    fallback = stored_config_for(app, mode_id, app_id)

    tweakable_keys(app, mode_id)
    |> Enum.reduce(config, fn key, acc ->
      if Map.has_key?(acc, key) do
        acc
      else
        case Map.fetch(fallback, key) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
      end
    end)
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
      has_presets: preset_persistable?(app),
      preset_label: preset_label(app)
    }
  end

  defp now_playing_dirty?(stored, overrides, tweakables) do
    persistable_tweakables = Enum.reject(tweakables, &Map.get(&1, :runtime))

    map_size(overrides) > 0 and
      Enum.any?(persistable_tweakables, fn %{key: key} ->
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

  defp schedule_change(%State{queue: []} = state) do
    %State{cancel_timer(state) | next_change_at_ms: nil}
  end

  defp schedule_change(%State{next_change_at_ms: deadline} = state)
       when is_integer(deadline) and deadline > 0 do
    remaining = max(deadline - now_ms(), 1)
    arm_timer(state, remaining, deadline)
  end

  defp schedule_change(%State{} = state), do: restart_countdown(state)

  defp restart_countdown(%State{queue: []} = state) do
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
      transition_duration_seconds: state.transition_duration_seconds,
      cycle_index: state.cycle_index,
      playing: state.playing,
      paused_remaining_ms: state.paused_remaining_ms,
      next_change_at_ms: state.next_change_at_ms,
      live: live,
      pending_entry: state.pending_entry,
      rotation_paused: state.rotation_paused,
      takeover_app_id: state.takeover_app_id,
      takeover_app_name: takeover_name(state.takeover_app_id),
      now_playing: build_now_playing(state)
    }
  end

  defp enrich_entry(nil), do: nil

  defp enrich_entry(%{app: app, mode_id: mode_id} = entry) do
    mode = find_mode(app, mode_id)

    base =
      Map.merge(entry, %{
        app_name: app_name(app),
        mode_name: mode && mode.name || mode_id,
        accent_color: mode && mode.accent_color || "#6d7cff",
        summary: mode && Map.get(mode, :summary) || "",
        builtin: mode && Map.get(mode, :builtin, true)
      })

    case Map.get(entry, :mask) do
      %{app: mask_app, mode_id: mask_mode_id} ->
        mask_mode = find_mode(mask_app, mask_mode_id)

        Map.merge(base, %{
          mask_app_name: app_name(mask_app),
          mask_mode_name: mask_mode && mask_mode.name || mask_mode_id
        })

      _ ->
        Map.put(base, :mask, nil)
    end
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

  defp entry_in_queue?(queue, entry), do: find_queue_index(queue, entry) != nil

  defp find_queue_index(queue, entry) do
    Enum.find_index(queue, &entries_match_front?(&1, entry))
  end

  defp reject_queue_entry(queue, entry) do
    case find_queue_index(queue, entry) do
      nil -> queue
      index -> List.delete_at(queue, index)
    end
  end

  defp entries_match_front?(%{app: app_a, mode_id: mode_a}, %{app: app_b, mode_id: mode_b}) do
    app_a == app_b and mode_a == mode_b
  end

  defp persist_queue_state(%State{} = state) do
    Task.start(fn -> persist_queue_state_sync(state) end)
    state
  end

  defp persist_queue_state_sync(%State{} = state) do
    attrs = %{
      queue: Enum.map(state.queue, &serialize_entry/1),
      cycle_index: state.cycle_index,
      cycle_interval_seconds: state.cycle_interval_seconds,
      transition_duration_seconds: state.transition_duration_seconds,
      playing: state.playing
    }

    PersistedState.save(attrs)
    state
  end

  @doc false
  def restore_queue_playback(%State{queue: []} = state), do: state

  def restore_queue_playback(%State{} = state) do
    index = clamp_index(state.cycle_index, state.queue)

    state
    |> Map.put(:playing, true)
    |> Map.put(:paused_remaining_ms, nil)
    |> Map.put(:cycle_index, index)
    |> commit_queue_entry_at_cycle_index()
    |> finalize_restore(index)
  end

  defp finalize_restore(%{live_entry: nil} = failed, index) when index != 0 do
    failed
    |> Map.put(:cycle_index, 0)
    |> commit_queue_entry_at_cycle_index()
    |> finalize_restore(0)
  end

  defp finalize_restore(%{live_entry: nil} = failed, index) do
    Logger.warning("InstallationTransport: could not restore queue playback at index #{index}")
    failed
  end

  defp finalize_restore(restored, _index), do: restart_countdown(restored)

  defp commit_queue_entry_at_cycle_index(%State{queue: queue, cycle_index: index} = state) do
    entry = Enum.at(queue, index)

    state
    |> Map.put(:pending_entry, entry)
    |> commit_pending_entry()
  end

  defp serialize_entry(%{app: app, mode_id: mode_id, mask: mask}) do
    %{
      "app" => Atom.to_string(app),
      "mode_id" => mode_id,
      "mask" => serialize_mask(mask)
    }
  end

  defp serialize_mask(nil), do: nil

  defp serialize_mask(%{app: app, mode_id: mode_id}) do
    %{"app" => Atom.to_string(app), "mode_id" => mode_id}
  end

  defp load_queue(nil), do: []

  defp load_queue(%PersistedState{queue: queue}) when is_list(queue) do
    queue
    |> Enum.map(fn entry ->
      normalize_entry(%{
        app: Map.fetch!(entry, "app"),
        mode_id: Map.fetch!(entry, "mode_id"),
        mask: case Map.get(entry, "mask") do
          nil -> nil
          mask -> %{app: Map.fetch!(mask, "app"), mode_id: Map.fetch!(mask, "mode_id")}
        end
      })
    end)
    |> Enum.reject(fn entry ->
      not (Code.ensure_loaded?(entry.app) and function_exported?(entry.app, :list_modes, 0))
    end)
  rescue
    _ -> []
  end

  defp normalize_entry(%{app: app, mode_id: id} = attrs) do
    app = normalize_app(app)
    id = to_string(id)

    mode_id =
      if preset_persistable?(app) do
        preset_normalize_mode_id(app, id)
      else
        id
      end

    %{app: app, mode_id: mode_id, mask: normalize_mask(Map.get(attrs, :mask))}
  end

  defp normalize_mask(nil), do: nil

  defp normalize_mask(%{app: app, mode_id: id}) do
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

  defp normalize_mask(_), do: nil

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

  defp normalize_transition_duration(seconds) when is_number(seconds) and seconds >= 0,
    do: seconds * 1.0

  defp normalize_transition_duration(_), do: @default_transition_duration_seconds

  defp transition_duration_ms(%State{transition_duration_seconds: seconds}) do
    seconds |> normalize_transition_duration() |> Kernel.*(1000) |> trunc() |> max(0)
  end

  defp interval_ms(%State{cycle_interval_seconds: seconds}) do
    seconds |> normalize_interval() |> Kernel.*(1000) |> trunc() |> max(1)
  end

  defp clamp_index(_index, []), do: 0
  defp clamp_index(index, queue), do: index |> max(0) |> min(length(queue) - 1)

  defp now_ms, do: System.os_time(:millisecond)

  defp app_mode_config(app, mode_id), do: apply(@app, :mode_config, [app, mode_id])
  defp app_apply_mode(app_id, app, mode_id), do: apply(@app, :apply_mode, [app_id, app, mode_id])
  defp app_mode_tweakables(app, mode_id), do: apply(@app, :mode_tweakables, [app, mode_id])
  defp app_now_playing_meta(app, config), do: apply(@app, :now_playing_meta, [app, config])
  defp app_name(app), do: apply(@app, :name, [app])
  defp app_list_modes(app), do: apply(@app, :list_modes, [app])

  defp preset_persistable?(app), do: apply(@app_mode_presets, :persistable?, [app])

  defp preset_get(app, mode_id), do: apply(@app_mode_presets, :get, [app, mode_id])
  defp preset_label(app), do: apply(@app_mode_presets, :preset_label, [app])

  defp preset_normalize_mode_id(app, mode_id),
    do: apply(@app_mode_presets, :normalize_mode_id, [app, mode_id])

  defp preset_summary(app, preset), do: apply(@app_mode_presets, :summary, [app, preset])
end
