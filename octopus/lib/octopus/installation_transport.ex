defmodule Octopus.InstallationTransport do
  @moduledoc """
  Installation-level rotation queue and transport.

  Owns the single queue of `{app, mode_id}` entries, one interval, and one
  countdown. Apps publish mode catalogs via `Octopus.App.list_modes/0` and
  `mode_config/1`; this module starts/selects apps and applies modes.
  """

  use GenServer

  alias Octopus.{App, AppManager, AppSupervisor}
  alias Octopus.Apps.PixelFun.ScenePresets

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
      :takeover_app_id
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
    do: GenServer.cast(__MODULE__, {:play_now, normalize_app(app), to_string(mode_id)})

  def queue_toggle(app, mode_id) do
    GenServer.cast(__MODULE__, {:queue_toggle, normalize_app(app), to_string(mode_id)})
  end

  def queue_remove(index) when is_integer(index),
    do: GenServer.cast(__MODULE__, {:queue_remove, index})

  def queue_move(index, dir) when is_integer(index),
    do: GenServer.cast(__MODULE__, {:queue_move, index, dir})

  def set_queue(entries) when is_list(entries),
    do: GenServer.cast(__MODULE__, {:set_queue, Enum.map(entries, &normalize_entry/1)})

  def set_interval(seconds) when is_number(seconds),
    do: GenServer.cast(__MODULE__, {:set_interval, seconds})

  def pause_rotation_for_takeover(app_id) when is_binary(app_id),
    do: GenServer.cast(__MODULE__, {:pause_rotation_for_takeover, app_id})

  def resume_rotation_after_takeover, do: GenServer.cast(__MODULE__, :resume_rotation_after_takeover)

  def launch_app(module) when is_atom(module),
    do: GenServer.cast(__MODULE__, {:launch_app, module})

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
      takeover_app_id: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_state(state), state}

  @impl true
  def handle_cast(:toggle_play, %State{playing: true} = state) do
    {:noreply, state |> pause() |> broadcast()}
  end

  def handle_cast(:toggle_play, %State{playing: false} = state) do
    {:noreply, state |> resume() |> broadcast()}
  end

  def handle_cast(:next, state) do
    {:noreply, state |> step(+1) |> broadcast()}
  end

  def handle_cast(:prev, state) do
    {:noreply, state |> step(-1) |> broadcast()}
  end

  def handle_cast({:play_now, app, mode_id}, state) do
    entry = %{app: app, mode_id: mode_id}

    state =
      state
      |> apply_entry(entry)
      |> maybe_jump_queue_index(entry)
      |> restart_countdown()

    {:noreply, broadcast(state)}
  end

  def handle_cast({:queue_toggle, app, mode_id}, state) do
    entry = %{app: app, mode_id: mode_id}

    new_queue =
      if entry_in_queue?(state.queue, entry) do
        List.delete(state.queue, entry)
      else
        state.queue ++ [entry]
      end

    {:noreply, state |> put_queue(new_queue) |> broadcast()}
  end

  def handle_cast({:queue_remove, index}, state) do
    new_queue = List.delete_at(state.queue, index)
    {:noreply, state |> put_queue(new_queue) |> broadcast()}
  end

  def handle_cast({:queue_move, index, dir}, state) do
    {:noreply, state |> move_queue(index, dir) |> broadcast()}
  end

  def handle_cast({:set_queue, entries}, state) do
    {:noreply, state |> put_queue(entries) |> broadcast()}
  end

  def handle_cast({:set_interval, seconds}, state) do
    {:noreply, %State{state | cycle_interval_seconds: normalize_interval(seconds)} |> broadcast()}
  end

  def handle_cast({:pause_rotation_for_takeover, app_id}, state) do
    state =
      state
      |> pause()
      |> then(fn s -> %State{s | rotation_paused: true, takeover_app_id: app_id} end)

    {:noreply, broadcast(state)}
  end

  def handle_cast(:resume_rotation_after_takeover, state) do
    state =
      %State{state | rotation_paused: false, takeover_app_id: nil}
      |> resume()

    {:noreply, broadcast(state)}
  end

  def handle_cast({:launch_app, module}, state) do
    cond do
      not App.rotation_eligible?(module) ->
        case AppSupervisor.start_or_select_app(module) do
          {:ok, app_id} ->
            AppManager.select_app(app_id)

            state =
              state
              |> pause()
              |> then(fn s -> %State{s | rotation_paused: true, takeover_app_id: app_id} end)

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
    index = clamp_index(state.cycle_index, queue)
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
    config = App.mode_config(app, mode_id)

    app_id =
      case AppSupervisor.find_running_app(app) do
        {:ok, id} ->
          if map_size(config) > 0, do: AppSupervisor.update_config(id, config)
          id

        :not_found ->
          case AppSupervisor.start_app(app, config: config) do
            {:ok, id} -> id
            _ -> nil
          end
      end

    if app_id do
      AppManager.select_app(app_id)
      App.apply_mode(app_id, app, mode_id)
      %State{state | live_entry: entry}
    else
      state
    end
  end

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
      takeover_app_name: takeover_name(state.takeover_app_id)
    }
  end

  defp enrich_entry(nil), do: nil

  defp enrich_entry(%{app: app, mode_id: mode_id} = entry) do
    mode = find_mode(app, mode_id)

    Map.merge(entry, %{
      app_name: App.name(app),
      mode_name: mode && mode.name || mode_id,
      accent_color: mode && mode.accent_color || "#6d7cff",
      summary: mode && Map.get(mode, :summary) || "",
      builtin: mode && Map.get(mode, :builtin, true)
    })
  end

  defp find_mode(Octopus.Apps.PixelFun, mode_id) do
    case ScenePresets.get(mode_id) do
      nil ->
        nil

      preset ->
        %{
          id: preset.id,
          name: preset.name,
          accent_color: preset.accent_color,
          summary: ScenePresets.summary(preset),
          builtin: preset.builtin
        }
    end
  end

  defp find_mode(app, mode_id) do
    Enum.find(App.list_modes(app), &(&1.id == mode_id))
  end

  defp takeover_name(nil), do: nil

  defp takeover_name(app_id) do
    case AppSupervisor.lookup_app(app_id) do
      {_pid, module} -> App.name(module)
      _ -> nil
    end
  end

  defp entry_in_queue?(queue, entry), do: entry in queue

  defp normalize_entry(%{app: app, mode_id: id}), do: %{app: normalize_app(app), mode_id: to_string(id)}

  defp normalize_app(app) when is_atom(app), do: app

  defp normalize_app(app) when is_binary(app) do
    Module.concat(Octopus.Apps, app)
  rescue
    _ -> app
  end

  defp normalize_interval(seconds) when is_number(seconds), do: seconds * 1.0 |> max(1.0)
  defp normalize_interval(_), do: @default_interval_seconds

  defp interval_ms(%State{cycle_interval_seconds: seconds}) do
    seconds |> normalize_interval() |> Kernel.*(1000) |> trunc() |> max(1)
  end

  defp clamp_index(_index, []), do: 0
  defp clamp_index(index, queue), do: index |> max(0) |> min(length(queue) - 1)

  defp now_ms, do: System.os_time(:millisecond)
end
