defmodule Octopus.Mixer do
  use GenServer
  require Logger

  alias Octopus.{Broadcaster, Protobuf, Canvas, AppManager, AppSupervisor, Installation}

  alias Octopus.Protobuf.{
    RGBFrame,
    WFrame,
    AudioFrame
  }

  @pubsub_topic "mixer"
  @pubsub_frames [RGBFrame, WFrame]
  @transition_duration 300
  @transition_frame_time trunc(1000 / 60)

  defmodule State do
    defstruct [
      # App display buffers and configuration
      # %{app_id => %{rgb_buffer: canvas, grayscale_buffer: canvas, config: %{}}}
      app_displays: %{},
      # :rgb | :grayscale | :masked
      output_mode: :rgb,
      # Cached installation info for performance
      display_info: nil,

      # Legacy fields (maintained for compatibility)
      rendered_app: nil,
      mask_app_id: nil,
      buffer_canvas: nil,

      # Transition system
      transition: nil,
      max_luminance: 255
    ]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # Display buffer management functions

  @doc """
  Creates display buffers for an app with the given configuration.
  """
  def create_display_buffers(app_id, config) do
    GenServer.call(__MODULE__, {:create_display_buffers, app_id, config})
  end

  @doc """
  Updates an app's display buffer with new canvas data.
  """
  def update_app_display(app_id, canvas, mode \\ :rgb, easing_interval_override \\ nil) do
    GenServer.cast(
      __MODULE__,
      {:update_app_display, app_id, canvas, mode, easing_interval_override}
    )
  end

  @doc """
  Returns cached display information for apps to use.
  """
  def get_display_info() do
    GenServer.call(__MODULE__, :get_display_info)
  end

  # Frame handling functions

  def handle_frame(app_id, %RGBFrame{} = frame) do
    # Split RGB frames to avoid UDP fragmenting. Can be removed when we fix the fragmenting in the firmware
    Protobuf.split_and_encode(frame)
    |> Enum.each(fn binary ->
      send_frame(binary, frame, app_id)
    end)
  end

  def handle_frame(app_id, %{} = frame) do
    # encode the frame in the app process, so any encoding errors get raised there
    Protobuf.encode(frame)
    |> send_frame(frame, app_id)
  end

  def handle_canvas(app_id, canvas) do
    GenServer.cast(__MODULE__, {:new_canvas, {app_id, canvas}})
  end

  defp send_frame(binary, frame, app_id) do
    GenServer.cast(__MODULE__, {:new_frame, {app_id, binary, frame}})
  end

  @doc """
  Subscribes to the mixer topic.

  Published messages:

  * `{:mixer, {:frame, %Octopus.Protobuf.RGBFrame{} = frame}}` - a new RGB frame was received from the selected app
  * `{:mixer, {:config, config}}` - mixer configuration changed
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @pubsub_topic)
  end

  def init(:ok) do
    # Subscribe to app events
    AppManager.subscribe()
    AppSupervisor.subscribe()

    # Initialize display info cache
    display_info = build_display_info(:gapped_panels)

    # Initialize buffer canvas
    buffer_width = Installation.num_panels() * Installation.panel_width()
    buffer_height = Installation.panel_height()

    {:ok,
     %State{display_info: display_info, buffer_canvas: Canvas.new(buffer_width, buffer_height)}}
  end

  # Display buffer management callbacks

  def handle_call({:create_display_buffers, app_id, config}, _from, %State{} = state) do
    # Build display info for this app's layout
    layout = Map.get(config, :layout, :gapped_panels)
    display_info = build_display_info(layout)

    width = display_info.width
    height = display_info.height

    # Create buffers based on app configuration
    rgb_buffer = if Map.get(config, :supports_rgb, true), do: Canvas.new(width, height), else: nil

    grayscale_buffer =
      if Map.get(config, :supports_grayscale, false), do: Canvas.new(width, height), else: nil

    app_display = %{
      rgb_buffer: rgb_buffer,
      grayscale_buffer: grayscale_buffer,
      config: config,
      display_info: display_info
    }

    new_app_displays = Map.put(state.app_displays, app_id, app_display)
    new_state = %State{state | app_displays: new_app_displays}

    {:reply, :ok, new_state}
  end

  def handle_call(:get_display_info, _from, %State{} = state) do
    # Return the default display info
    {:reply, state.display_info, state}
  end

  def handle_call({:get_display_info, app_id}, _from, %State{} = state) do
    # Return app-specific display info
    case Map.get(state.app_displays, app_id) do
      %{display_info: display_info} -> {:reply, display_info, state}
      nil -> {:reply, nil, state}
    end
  end

  # Handle RGB display buffer updates
  def handle_cast(
        {:update_app_display, app_id, canvas, :rgb, easing_interval_override},
        %State{} = state
      ) do
    case Map.get(state.app_displays, app_id) do
      nil ->
        # App not configured yet
        {:noreply, state}

      app_display ->
        updated_display = %{app_display | rgb_buffer: canvas}
        new_app_displays = Map.put(state.app_displays, app_id, updated_display)
        new_state = %State{state | app_displays: new_app_displays}

        if state.rendered_app == app_id do
          display_info = updated_display.display_info

          easing_interval =
            easing_interval_override || Map.get(updated_display.config, :easing_interval, 0)

          # Apply mask if in masked mode
          frame =
            if state.output_mode == :masked and state.mask_app_id do
              mask_display = Map.get(new_state.app_displays, state.mask_app_id)

              if mask_display do
                mask_canvas = get_mask_canvas(mask_display)

                if mask_canvas do
                  # RGB frame with masking
                  canvas_to_frame_with_mask(
                    canvas,
                    mask_canvas,
                    display_info,
                    easing_interval,
                    :rgb,
                    app_display
                  )
                else
                  canvas_to_frame(canvas, display_info, easing_interval, app_display)
                end
              else
                # RGB frame without masking
                canvas_to_frame(canvas, display_info, easing_interval, app_display)
              end
            else
              # RGB frame without masking
              canvas_to_frame(canvas, display_info, easing_interval, app_display)
            end

          frame
          |> Protobuf.split_and_encode()
          |> Enum.each(fn binary ->
            send_frame(binary, frame)
          end)
        end

        {:noreply, new_state}
    end
  end

  # Handle grayscale display buffer updates
  def handle_cast(
        {:update_app_display, app_id, canvas, :grayscale, easing_interval_override},
        %State{} = state
      ) do
    case Map.get(state.app_displays, app_id) do
      nil ->
        # App not configured yet
        {:noreply, state}

      app_display ->
        updated_display = %{app_display | grayscale_buffer: canvas}
        new_app_displays = Map.put(state.app_displays, app_id, updated_display)
        new_state = %State{state | app_displays: new_app_displays}

        # If this app is currently selected, generate and send frame
        if state.rendered_app == app_id do
          display_info = updated_display.display_info

          easing_interval =
            easing_interval_override || Map.get(updated_display.config, :easing_interval, 0)

          # Apply mask if in masked mode
          if state.output_mode == :masked and state.mask_app_id do
            mask_display = Map.get(new_state.app_displays, state.mask_app_id)

            if mask_display do
              mask_canvas = get_mask_canvas(mask_display)

              if mask_canvas do
                # Send WFrame with masking
                frame =
                  canvas_to_wframe_with_mask(
                    canvas,
                    mask_canvas,
                    display_info,
                    easing_interval,
                    app_display
                  )

                binary = Protobuf.encode(frame)
                send_frame(binary, frame)
              else
                # Send WFrame without masking
                frame = canvas_to_wframe(canvas, display_info, easing_interval, app_display)
                binary = Protobuf.encode(frame)
                send_frame(binary, frame)
              end
            else
              # Send WFrame without masking
              frame = canvas_to_wframe(canvas, display_info, easing_interval, app_display)
              binary = Protobuf.encode(frame)
              send_frame(binary, frame)
            end
          else
            # Send WFrame without masking
            frame = canvas_to_wframe(canvas, display_info, easing_interval, app_display)
            binary = Protobuf.encode(frame)
            send_frame(binary, frame)
          end
        end

        {:noreply, new_state}
    end
  end

  # Legacy callbacks

  def handle_cast({:new_frame, {app_id, binary, f}}, %State{rendered_app: rendered_app} = state) do
    case rendered_app do
      {^app_id, _} -> send_frame(binary, f)
      {_, ^app_id} -> send_frame(binary, f)
      ^app_id -> send_frame(binary, f)
      _ -> :noop
    end

    {:noreply, state}
  end

  def handle_cast(
        {:new_canvas, {left_app_id, canvas}},
        %State{rendered_app: {left_app_id, _}} = state
      ) do
    handle_new_canvas(state, canvas, {0, 0})
  end

  def handle_cast(
        {:new_canvas, {right_app_id, canvas}},
        %State{rendered_app: {_, right_app_id}} = state
      ) do
    handle_new_canvas(state, canvas, {40, 0})
  end

  def handle_cast({:new_canvas, _}, state), do: {:noreply, state}

  def handle_cast(:stop_audio_playback, state) do
    do_stop_audio_playback()
    {:noreply, state}
  end

  # Handle app selection changes from AppManager
  def handle_info({:app_manager, {:selected_app, selected_app}}, %State{} = state) do
    # Check if transitions are enabled
    transitions_enabled = Application.get_env(:octopus, :enable_transitions, true)

    # Start transition if switching to a different app and transitions are enabled
    if state.rendered_app != selected_app and state.transition == nil and transitions_enabled do
      # Start fade out transition, store target app for later
      state = %State{state | transition: {:out, @transition_duration, selected_app}}
      Broadcaster.set_luminance(state.max_luminance)
      schedule_transition()
      {:noreply, state}
    else
      # No transition needed, transition already in progress, or transitions disabled
      state = %State{state | rendered_app: selected_app}
      state = update_output_mode(state)
      {:noreply, state}
    end
  end

  def handle_info({:app_manager, {:mask_app, mask_app_id}}, %State{} = state) do
    # Update mask app and output mode
    state = %State{state | mask_app_id: mask_app_id}
    state = update_output_mode(state)
    {:noreply, state}
  end

  # Handle app lifecycle events from AppManager
  def handle_info({:app_manager, {:app_lifecycle, _app_id, _event}}, %State{} = state) do
    {:noreply, state}
  end

  # Handle app stopping events from AppSupervisor
  def handle_info({:apps, {:stopped, app_id}}, %State{} = state) do
    # Remove app's display buffers
    new_app_displays = Map.delete(state.app_displays, app_id)
    new_state = %State{state | app_displays: new_app_displays}
    {:noreply, new_state}
  end

  # Ignore other app supervisor events
  def handle_info({:apps, _}, %State{} = state) do
    {:noreply, state}
  end

  ### App Transitions ###

  def handle_info(:transition, %State{transition: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:out, time, target_app}} = state)
      when time <= 0 do
    # Fade out complete, switch to target app and start fade in
    state = %State{
      state
      | rendered_app: target_app,
        transition: {:in, @transition_duration}
    }

    state = update_output_mode(state)
    Broadcaster.set_luminance(0)
    schedule_transition()

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:out, time, target_app}} = state) do
    # Continue fade out
    state = %State{
      state
      | transition: {:out, time - @transition_frame_time, target_app}
    }

    (Easing.cubic_in(time / @transition_duration) * state.max_luminance)
    |> round()
    |> Broadcaster.set_luminance()

    schedule_transition()

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:in, time}} = state) when time <= 0 do
    # Fade in complete, transition finished
    state = %State{state | transition: nil}
    Broadcaster.set_luminance(state.max_luminance)

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:in, time}} = state) do
    # Continue fade in
    state = %State{
      state
      | transition: {:in, time - @transition_frame_time}
    }

    ((1 - Easing.cubic_out(time / @transition_duration)) * state.max_luminance)
    |> round()
    |> Broadcaster.set_luminance()

    schedule_transition()

    {:noreply, state}
  end

  ### End App Transitions ###

  defp send_frame(binary, %frame_type{} = frame) do
    if frame_type in @pubsub_frames do
      Phoenix.PubSub.broadcast(Octopus.PubSub, @pubsub_topic, {:mixer, {:frame, frame}})
    end

    Broadcaster.send_binary(binary)
  end

  defp schedule_transition() do
    Process.send_after(self(), :transition, @transition_frame_time)
  end

  defp handle_new_canvas(state, canvas, offset) do
    buffer_canvas =
      state.buffer_canvas
      |> Canvas.clear()
      |> Canvas.overlay(canvas, offset: offset)

    # Generate frame for buffer canvas
    panel_width = Installation.panel_width()

    data =
      for window <- 0..(div(buffer_canvas.width, panel_width) - 1),
          y <- 0..(buffer_canvas.height - 1),
          x <- 0..(panel_width - 1),
          {r, g, b} = Canvas.get_pixel(buffer_canvas, {window * panel_width + x, y}),
          do: [r, g, b]

    frame = %RGBFrame{data: data |> IO.iodata_to_binary(), easing_interval: 0}
    binary = Protobuf.encode(frame)
    send_frame(binary, frame)

    {:noreply, %State{state | buffer_canvas: buffer_canvas}}
  end

  defp do_stop_audio_playback() do
    for channel <- 1..Installation.num_panels() do
      %AudioFrame{
        channel: channel,
        stop: true
      }
      |> Protobuf.encode()
      |> Broadcaster.send_binary()
    end
  end

  # Display layout and frame generation functions

  # Converts a canvas to frame using layout-aware pixel extraction.
  defp canvas_to_frame(canvas, display_info, easing_interval, app_display) do
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    # Iterate through panels in order
    data =
      for panel_id <- 0..(Installation.num_panels() - 1),
          y <- 0..(panel_height - 1),
          x <- 0..(panel_width - 1) do
        # Calculate virtual canvas coordinates for this panel pixel
        {panel_x_start, _} = display_info.panel_range.(panel_id, :x)
        canvas_x = panel_x_start + x
        canvas_y = y

        # Get pixel value and format for RGB frame
        case Canvas.get_pixel(canvas, {canvas_x, canvas_y}) do
          {r, g, b} -> [r, g, b]
          gray when is_integer(gray) -> [gray, gray, gray]
        end
      end

    %RGBFrame{
      data: data |> IO.iodata_to_binary(),
      easing_interval: easing_interval,
      keep_w: app_display.config.merge_rgbw
    }
  end

  # Converts a grayscale canvas to WFrame using layout-aware pixel extraction.
  defp canvas_to_wframe(canvas, display_info, easing_interval, app_display) do
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    # Iterate through panels in order
    data =
      for panel_id <- 0..(Installation.num_panels() - 1),
          y <- 0..(panel_height - 1),
          x <- 0..(panel_width - 1) do
        # Calculate virtual canvas coordinates for this panel pixel
        {panel_x_start, _} = display_info.panel_range.(panel_id, :x)
        canvas_x = panel_x_start + x
        canvas_y = y

        # Get pixel value and convert to grayscale for WFrame
        case Canvas.get_pixel(canvas, {canvas_x, canvas_y}) do
          {r, g, b} ->
            %Chameleon.HSL{l: l} = Chameleon.RGB.new(r, g, b) |> Chameleon.convert(Chameleon.HSL)
            trunc(l * 2.55)

          gray when is_integer(gray) ->
            gray
        end
      end

    %WFrame{
      data: data |> IO.iodata_to_binary(),
      easing_interval: easing_interval,
      keep_rgb: app_display.config.merge_rgbw
    }
  end

  # Converts canvas to frame with masking applied during frame generation
  defp canvas_to_frame_with_mask(
         canvas,
         mask_canvas,
         display_info,
         easing_interval,
         output_type,
         app_display
       ) do
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    # Ensure mask canvas is in grayscale format for masking
    grayscale_mask = Canvas.to_grayscale(mask_canvas)

    # Iterate through panels in order with masking applied
    data =
      for panel_id <- 0..(Installation.num_panels() - 1),
          y <- 0..(panel_height - 1),
          x <- 0..(panel_width - 1) do
        # Calculate virtual canvas coordinates for this panel pixel
        {panel_x_start, _} = display_info.panel_range.(panel_id, :x)
        canvas_x = panel_x_start + x
        canvas_y = y

        # Get pixel value from main app's virtual canvas
        pixel_value = Canvas.get_pixel(canvas, {canvas_x, canvas_y})

        # Get mask value from the same virtual coordinates in the mask canvas
        mask_value = Canvas.get_pixel(grayscale_mask, {canvas_x, canvas_y})

        # Apply masking based on output type
        case output_type do
          :rgb ->
            case pixel_value do
              {r, g, b} ->
                mask_ratio = mask_value / 255.0
                [trunc(r * mask_ratio), trunc(g * mask_ratio), trunc(b * mask_ratio)]

              _ ->
                [0, 0, 0]
            end

          :grayscale ->
            gray_value =
              case pixel_value do
                {r, g, b} -> Canvas.rgb_to_grayscale(r, g, b)
                gray when is_integer(gray) -> gray
              end

            mask_ratio = mask_value / 255.0
            masked_gray = trunc(gray_value * mask_ratio)
            [masked_gray, masked_gray, masked_gray]
        end
      end

    %RGBFrame{
      data: data |> IO.iodata_to_binary(),
      easing_interval: easing_interval,
      keep_w: app_display.config.merge_rgbw
    }
  end

  # Converts canvas to wframe with masking applied during frame generation
  defp canvas_to_wframe_with_mask(canvas, mask_canvas, display_info, easing_interval, app_display) do
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    # Ensure mask canvas is in grayscale format for masking
    grayscale_mask = Canvas.to_grayscale(mask_canvas)

    # Iterate through panels in order with masking applied
    data =
      for panel_id <- 0..(Installation.num_panels() - 1),
          y <- 0..(panel_height - 1),
          x <- 0..(panel_width - 1) do
        # Calculate virtual canvas coordinates for this panel pixel
        {panel_x_start, _} = display_info.panel_range.(panel_id, :x)
        canvas_x = panel_x_start + x
        canvas_y = y

        # Get pixel value from main app's virtual canvas
        pixel_value = Canvas.get_pixel(canvas, {canvas_x, canvas_y})

        # Get mask value from the same virtual coordinates in the mask canvas
        mask_value = Canvas.get_pixel(grayscale_mask, {canvas_x, canvas_y})

        # Convert to grayscale and apply masking
        gray_value =
          case pixel_value do
            {r, g, b} -> Canvas.rgb_to_grayscale(r, g, b)
            gray when is_integer(gray) -> gray
          end

        mask_ratio = mask_value / 255.0
        trunc(gray_value * mask_ratio)
      end

    %WFrame{
      data: data |> IO.iodata_to_binary(),
      easing_interval: easing_interval,
      keep_rgb: app_display.config.merge_rgbw
    }
  end

  defp build_display_info(layout) do
    # Build layout-specific functions based on layout type
    {panel_range_fn, width} =
      case layout do
        :adjacent_panels ->
          range_fn = fn panel_id, axis ->
            case axis do
              :x ->
                panel_width = Installation.panel_width()
                x_offset = panel_id * panel_width
                {x_offset, x_offset + panel_width - 1}

              :y ->
                panel_height = Installation.panel_height()
                {0, panel_height - 1}
            end
          end

          # Panels are directly adjacent, no gaps
          calculated_width = Installation.num_panels() * Installation.panel_width()
          {range_fn, calculated_width}

        :gapped_panels ->
          range_fn = fn panel_id, axis ->
            case axis do
              :x ->
                panel_width = Installation.panel_width()
                panel_gap = Installation.panel_gap()
                x_offset = panel_id * (panel_width + panel_gap)
                {x_offset, x_offset + panel_width - 1}

              :y ->
                panel_height = Installation.panel_height()
                {0, panel_height - 1}
            end
          end

          # Gaps only between panels, not after the last one
          num_panels = Installation.num_panels()
          panel_width = Installation.panel_width()
          panel_gap = Installation.panel_gap()
          calculated_width = num_panels * panel_width + (num_panels - 1) * panel_gap
          {range_fn, calculated_width}

        :gapped_panels_wrapped ->
          range_fn = fn panel_id, axis ->
            case axis do
              :x ->
                panel_width = Installation.panel_width()
                panel_gap = Installation.panel_gap()
                x_offset = panel_id * (panel_width + panel_gap)
                {x_offset, x_offset + panel_width - 1}

              :y ->
                panel_height = Installation.panel_height()
                {0, panel_height - 1}
            end
          end

          # Gaps between panels AND after the last panel for wrapping
          num_panels = Installation.num_panels()
          panel_width = Installation.panel_width()
          panel_gap = Installation.panel_gap()
          calculated_width = num_panels * (panel_width + panel_gap)
          {range_fn, calculated_width}
      end

    panel_at_coord_fn = fn x, y ->
      num_panels = Installation.num_panels()

      Enum.find(0..(num_panels - 1), fn panel_id ->
        {start_x, end_x} = panel_range_fn.(panel_id, :x)
        {start_y, end_y} = panel_range_fn.(panel_id, :y)
        x >= start_x and x <= end_x and y >= start_y and y <= end_y
      end) || :not_found
    end

    panel_to_global_coords_fn = fn panel_id, local_x, local_y ->
      num_panels = Installation.num_panels()

      if panel_id >= 0 and panel_id < num_panels do
        {x_offset, _} = panel_range_fn.(panel_id, :x)
        {_, y_offset} = panel_range_fn.(panel_id, :y)
        {x_offset + local_x, y_offset + local_y}
      else
        :invalid_panel
      end
    end

    %{
      layout: layout,
      width: width,
      height: Installation.panel_height(),
      panel_width: Installation.panel_width(),
      panel_height: Installation.panel_height(),
      num_panels: Installation.num_panels(),
      panel_gap: Installation.panel_gap(),
      panel_range: panel_range_fn,
      panel_at_coord: panel_at_coord_fn,
      panel_to_global_coords: panel_to_global_coords_fn
    }
  end

  @doc """
  Returns app-specific display information based on the app's layout configuration.
  """
  def get_app_display_info(app_id) do
    GenServer.call(__MODULE__, {:get_display_info, app_id})
  end

  defp update_output_mode(%State{rendered_app: main, mask_app_id: mask} = state) do
    cond do
      main && mask -> %State{state | output_mode: :masked}
      main -> %State{state | output_mode: :rgb}
      true -> %State{state | output_mode: :rgb}
    end
  end

  # Helper to get mask canvas from app display
  defp get_mask_canvas(mask_display) do
    cond do
      # Prefer grayscale buffer if available
      mask_display.grayscale_buffer ->
        mask_display.grayscale_buffer

      # Convert RGB buffer to grayscale for masking
      mask_display.rgb_buffer ->
        Canvas.to_grayscale(mask_display.rgb_buffer)

      # No buffer available
      true ->
        nil
    end
  end
end
