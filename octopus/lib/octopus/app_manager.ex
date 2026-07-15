defmodule Octopus.AppManager do
  @moduledoc """
  Centralized app lifecycle and selection management.

  Manages which apps are selected for different purposes (single app, dual-side apps)
  and handles app lifecycle events like APP_SELECTED/APP_DESELECTED notifications.

  This module extracts app management concerns from the Mixer, allowing the Mixer
  to focus purely on visual mixing and transitions.
  """

  use GenServer

  alias Octopus.AppSupervisor
  alias Octopus.Events.Event.Lifecycle

  @topic "app_manager"

  defmodule State do
    defstruct selected_app: nil,
              last_selected_app: nil,
              mask_app_id: nil
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Selects the app with the given `app_id` to be shown (main app).
  """
  def select_app(app_id) do
    GenServer.cast(__MODULE__, {:select_app, app_id})
  end

  @doc """
  Selects the app for a specific side (for dual-side apps).
  """
  def select_app(app_id, side) when side in [:left, :right] do
    GenServer.cast(__MODULE__, {:select_app, app_id, side})
  end

  @doc """
  Returns the currently selected app (main app).
  """
  def get_selected_app() do
    GenServer.call(__MODULE__, :get_selected_app)
  end

  @doc """
  Sets the mask app (grayscale mask).
  """
  def set_mask_app(mask_app_id) do
    GenServer.cast(__MODULE__, {:set_mask_app, mask_app_id})
  end

  @doc """
  Returns the currently selected mask app.
  """
  def get_mask_app() do
    GenServer.call(__MODULE__, :get_mask_app)
  end

  @doc """
  Subscribes to app manager events.

  Published messages:
  * `{:app_manager, {:selected_app, app_id}}` - the selected app changed
  * `{:app_manager, {:mask_app, mask_app_id}}` - the mask app changed
  * `{:app_manager, {:app_lifecycle, app_id, :selected | :deselected}}` - app lifecycle events
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  def init(:ok) do
    # Subscribe to app stopping events
    AppSupervisor.subscribe()
    {:ok, %State{}}
  end

  def handle_call(:get_selected_app, _from, %State{selected_app: selected_app} = state) do
    {:reply, selected_app, state}
  end

  def handle_call(:get_mask_app, _from, %State{mask_app_id: mask_app_id} = state) do
    {:reply, mask_app_id, state}
  end

  # Handle dual-side app selection (for games like Blocks, etc.)
  def handle_cast({:select_app, next_app_id, side}, %State{} = state) do
    selected_app =
      case {state.selected_app, side} do
        {{_, right}, :left} -> {next_app_id, right}
        {{left, _}, :right} -> {left, next_app_id}
        {_, :left} -> {next_app_id, nil}
        {_, :right} -> {nil, next_app_id}
      end

    # If the mask app is the same as the new main app, clear the mask
    mask_app_id = if state.mask_app_id == next_app_id, do: nil, else: state.mask_app_id

    state = %State{
      state
      | selected_app: selected_app,
        last_selected_app: state.selected_app,
        mask_app_id: mask_app_id
    }

    broadcast_selected_app(state)
    broadcast_mask_app(state)
    send_lifecycle_events(state)

    {:noreply, state}
  end

  # Handle single app selection
  def handle_cast({:select_app, next_app_id}, %State{} = state) do
    # If the mask app is the same as the new main app, clear the mask
    mask_app_id = if state.mask_app_id == next_app_id, do: nil, else: state.mask_app_id

    state = %State{
      state
      | selected_app: next_app_id,
        last_selected_app: state.selected_app,
        mask_app_id: mask_app_id
    }

    broadcast_selected_app(state)
    broadcast_mask_app(state)
    send_lifecycle_events(state)

    {:noreply, state}
  end

  # Handle mask app selection
  def handle_cast({:set_mask_app, mask_app_id}, %State{} = state) do
    # Check if the mask app is a grayscale app and currently selected
    is_selected_grayscale_app =
      mask_app_id == state.selected_app and supports_grayscale?(mask_app_id)

    # If the mask app is the same as the current mask app, toggle it off (clear mask)
    # If it's a selected grayscale app, deselect it and set as mask
    # Otherwise, if it's the same as the main app (non-grayscale), clear mask
    {new_selected_app, new_mask_app_id} =
      cond do
        # Toggle off if same mask app clicked again
        mask_app_id == state.mask_app_id ->
          {state.selected_app, nil}

        # If it's a selected grayscale app, deselect and set as mask
        is_selected_grayscale_app ->
          {nil, mask_app_id}

        # If the mask app is the same as the main app (non-grayscale), clear mask
        mask_app_id == state.selected_app ->
          {state.selected_app, nil}

        # Normal case: set as mask
        true ->
          {state.selected_app, mask_app_id}
      end

    state = %State{
      state
      | selected_app: new_selected_app,
        last_selected_app: state.selected_app,
        mask_app_id: new_mask_app_id
    }

    broadcast_selected_app(state)
    broadcast_mask_app(state)
    send_lifecycle_events(state)
    {:noreply, state}
  end

  # Handle app stopping events to clear mask if mask app is stopped
  def handle_info({:apps, {:stopped, app_id}}, %State{} = state) do
    # If the stopped app was the mask app, clear the mask
    new_mask_app_id = if state.mask_app_id == app_id, do: nil, else: state.mask_app_id

    # If the stopped app was the selected app, clear it too
    new_selected_app = if state.selected_app == app_id, do: nil, else: state.selected_app

    new_state = %State{state | mask_app_id: new_mask_app_id, selected_app: new_selected_app}

    # Broadcast changes if they occurred
    if new_mask_app_id != state.mask_app_id do
      broadcast_mask_app(new_state)
    end

    if new_selected_app != state.selected_app do
      broadcast_selected_app(new_state)
    end

    {:noreply, new_state}
  end

  # Ignore other app supervisor events
  def handle_info({:apps, _}, %State{} = state) do
    {:noreply, state}
  end

  # Broadcast app selection changes
  defp broadcast_selected_app(%State{} = state) do
    selected =
      case state.selected_app do
        # For dual-side apps, we don't broadcast a single selected app
        {_, _} -> nil
        app_id -> app_id
      end

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:app_manager, {:selected_app, selected}}
    )
  end

  defp broadcast_mask_app(%State{} = state) do
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:app_manager, {:mask_app, state.mask_app_id}}
    )
  end

  # Send APP_SELECTED/APP_DESELECTED lifecycle events to apps
  defp send_lifecycle_events(%State{selected_app: {_, _}} = _state) do
    # For dual-side apps, we don't send lifecycle events
    # (This matches current Mixer behavior)
    :ok
  end

  defp send_lifecycle_events(%State{} = state) do
    # Send APP_SELECTED to the newly selected app
    if state.selected_app do
      AppSupervisor.send_event(state.selected_app, Lifecycle.app_selected())

      Phoenix.PubSub.broadcast(
        Octopus.PubSub,
        @topic,
        {:app_manager, {:app_lifecycle, state.selected_app, :selected}}
      )
    end

    # Send APP_DESELECTED to the previously selected app
    if state.last_selected_app && state.last_selected_app != state.selected_app do
      AppSupervisor.send_event(state.last_selected_app, Lifecycle.app_deselected())

      Phoenix.PubSub.broadcast(
        Octopus.PubSub,
        @topic,
        {:app_manager, {:app_lifecycle, state.last_selected_app, :deselected}}
      )
    end
  end

  @doc """
  Returns true if the running app with the given app_id supports greyscale output.
  """
  def supports_grayscale?(app_id) do
    try do
      {_pid, module} = AppSupervisor.lookup_app(app_id)
      output_type = apply(module, :output_type, [])
      output_type in [:grayscale, :both]
    rescue
      _ -> false
    end
  end

  @doc """
  Returns true if the given app module supports greyscale output (without a running instance).
  """
  def supports_grayscale_module?(module) when is_atom(module) do
    try do
      apply(module, :output_type, []) in [:grayscale, :both]
    rescue
      _ -> false
    end
  end
end
