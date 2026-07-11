defmodule Octopus.Apps.Ocean do
  use Octopus.App, category: :animation

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.{Canvas, WebP}

  @fps 30

  defmodule State do
    defstruct [
      :time,
      :wave_strength,
      :damping,
      :width,
      :height,
      :water_level_ratio,
      :water_level,
      # Replace wave processes with direct wave data
      :background_waves,
      :interaction_waves,
      # Track when the system started for decay calculations
      :start_time,
      # Track button press visual feedback
      :button_flashes,
      # Track last user interaction for inactivity detection
      :last_activity_time,
      # Timer reference for inactivity reactivation
      :inactivity_timer_ref
    ]
  end

  # Wave data structure for Gerstner waves
  defmodule Wave do
    defstruct [
      # Wave height
      :amplitude,
      # Distance between wave peaks
      :wavelength,
      # Wave direction (0-2π radians)
      :direction,
      # Phase offset
      :phase,
      # Derived from wavelength
      :frequency,
      # Derived from wavelength (dispersion relation)
      :speed,
      # When wave was created (for interaction waves)
      :birth_time,
      # How fast interaction waves fade
      :decay_rate,
      # Original amplitude for decay calculations
      :initial_amplitude,
      # Whether this is a persistent wind wave
      :is_wind_wave
    ]
  end

  def name(), do: "Ocean"

  def icon(), do: WebP.load("ocean")

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    (apply(@mode_presets, :config_for, [__MODULE__, mode_id]) ||
       legacy_mode_config(apply(@mode_presets, :mode_slug, [mode_id])))
  end

  def builtin_presets do
    [
      %{
        slug: "ocean",
        name: "Ocean",
        accent_color: "#2980B9",
        config: legacy_mode_config("ocean")
      }
    ]
  end

  def legacy_mode_config("ocean") do
    %{wave_strength: 1.0, damping: 0.95, water_level: 0.6}
  end

  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("ocean") do
    [
      %{
        key: :wave_strength,
        label: "Wave strength",
        type: :slider,
        min: 0.1,
        max: 3.0,
        step: 0.1,
        default: 1.0
      },
      %{
        key: :damping,
        label: "Surface damping",
        type: :slider,
        min: 0.8,
        max: 0.99,
        step: 0.01,
        default: 0.95
      },
      %{
        key: :water_level,
        label: "Water level",
        type: :slider,
        min: 0.3,
        max: 0.9,
        step: 0.05,
        default: 0.6
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def now_playing_meta(config) do
    strength = Map.get(config, :wave_strength, 1.0)
    damping = Map.get(config, :damping, 0.95)
    level = Map.get(config, :water_level, 0.6)

    [
      "strength #{format_num(strength)}",
      "damping #{format_num(damping)}",
      "level #{round(level * 100)}%",
      "Press panels for waves"
    ]
  end

  def compatible? do
    Octopus.App.get_installation_info().panel_count >= 1
  end

  def config_schema do
    %{
      wave_strength: {"Wave Strength", :float, %{default: 1.0, min: 0.1, max: 3.0}},
      damping: {"Surface Damping", :float, %{default: 0.95, min: 0.8, max: 0.99}},
      water_level: {"Water Level", :float, %{default: 0.6, min: 0.3, max: 0.9, step: 0.05}}
    }
  end

  def app_init(config) do
    # Configure display using new unified API - gapped_panels_wrapped layout for seamless wrapping
    Octopus.App.configure_display(layout: :gapped_panels_wrapped)
    Octopus.App.subscribe_to_button_events()

    :timer.send_interval(trunc(1000 / @fps), :tick)

    # Get display info instead of VirtualMatrix
    display_info = Octopus.App.get_display_info()
    width = display_info.width
    height = display_info.height

    state = %State{
      time: 0,
      width: width,
      height: height,
      interaction_waves: [],
      start_time: :os.system_time(:millisecond),
      button_flashes: [],
      last_activity_time: :os.system_time(:millisecond),
      inactivity_timer_ref: nil
    }

    {:ok, apply_config(state, config)}
  end

  def handle_config(config, %State{} = state) do
    {:noreply, apply_config(state, config)}
  end

  def get_config(%State{} = state) do
    %{
      wave_strength: state.wave_strength,
      damping: state.damping,
      water_level: state.water_level_ratio
    }
  end

  # Handle button press events - create interaction wave
  def handle_event(
        %InputEvent{type: :button, action: :press, button: button_number},
        %State{} = state
      ) do
    # Logger.info("Ocean: Button pressed: #{button_number}")

    # Convert to 0-based indexing
    button_index = button_number - 1

    # Logger.info("Ocean: Creating interaction wave for button #{button_index}")

    # Cancel existing inactivity timer if it exists
    if state.inactivity_timer_ref do
      :timer.cancel(state.inactivity_timer_ref)
    end

    # Update last activity time
    current_time = :os.system_time(:millisecond)

    state = create_interaction_wave(state, button_index)
    {:noreply, %{state | last_activity_time: current_time, inactivity_timer_ref: nil}}
  end

  def handle_event(%InputEvent{}, %State{} = state) do
    # Logger.debug("Ocean: Ignoring input event")
    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    # Update time
    new_time = state.time + 1 / @fps

    # Clean up old interaction waves
    current_time = :os.system_time(:millisecond)

    active_interaction_waves =
      Enum.filter(state.interaction_waves, fn wave ->
        age_seconds = (current_time - wave.birth_time) / 1000.0
        # Remove waves older than 8 seconds
        age_seconds < 8.0
      end)

    # Clean up expired button flashes
    active_button_flashes =
      Enum.filter(state.button_flashes, fn flash ->
        age_ms = current_time - flash.start_time
        age_ms < flash.duration
      end)

    # Check if we need to start inactivity timer
    updated_state =
      check_and_start_inactivity_timer(state, current_time, active_interaction_waves)

    # Render the water using Gerstner wave calculations
    canvas =
      render_gerstner_water(
        updated_state,
        new_time,
        active_interaction_waves,
        active_button_flashes
      )

    # Use new unified display API
    Octopus.App.update_display(canvas)

    {:noreply,
     %{
       updated_state
       | time: new_time,
         interaction_waves: active_interaction_waves,
         button_flashes: active_button_flashes
     }}
  end

  # Handle inactivity timer - reactivate initial waves
  def handle_info(:reactivate_waves, %State{} = state) do
    # Logger.info("Ocean: Reactivating waves after inactivity period")

    # Generate new initial waves (same as startup)
    new_background_waves = generate_background_waves(state.width, state.wave_strength)

    {:noreply, %{state | background_waves: new_background_waves, inactivity_timer_ref: nil}}
  end

  # Check if ocean has calmed down and start inactivity timer if needed
  defp check_and_start_inactivity_timer(state, current_time, active_interaction_waves) do
    # Only check if we don't already have a timer running
    if state.inactivity_timer_ref == nil do
      # Check if ocean has calmed down:
      # 1. No active interaction waves
      # 2. All background waves have decayed to minimal levels
      ocean_is_calm =
        Enum.empty?(active_interaction_waves) and
          all_background_waves_decayed?(state.background_waves, current_time)

      if ocean_is_calm do
        # Check if enough time has passed since last activity
        time_since_activity = current_time - state.last_activity_time

        # 2 seconds buffer after waves calm down
        if time_since_activity >= 2000 do
          # Logger.info("Ocean: Ocean has calmed down, starting 15-second inactivity timer")

          # Start 15-second timer
          {:ok, timer_ref} = :timer.send_after(15_000, :reactivate_waves)

          %{state | inactivity_timer_ref: timer_ref}
        else
          state
        end
      else
        state
      end
    else
      state
    end
  end

  # Check if all background waves have decayed to minimal levels
  defp all_background_waves_decayed?(background_waves, current_time) do
    Enum.all?(background_waves, fn wave ->
      if wave.is_wind_wave do
        # Wind waves are always active, so they don't count for "calmed down"
        true
      else
        # Check if non-wind waves have decayed significantly
        if wave.birth_time do
          age_seconds = (current_time - wave.birth_time) / 1000.0
          decay_factor = :math.pow(wave.decay_rate, age_seconds * 0.8)
          current_amplitude = wave.amplitude * decay_factor

          # Consider wave "decayed" if it's less than 20% of original amplitude
          current_amplitude < wave.initial_amplitude * 0.2
        else
          # Waves without birth_time are considered persistent
          false
        end
      end
    end)
  end

  # Generate realistic background waves using simplified Phillips spectrum
  defp generate_background_waves(width, wave_strength) do
    # Create initial waves with different wavelengths that will decay over time
    initial_wavelengths = [
      # Long swells
      width * 0.8,
      # Medium waves
      width * 0.4,
      # Shorter waves
      width * 0.2,
      # Small waves
      width * 0.1
    ]

    # Create persistent tiny wind waves (very small amplitude)
    wind_wavelengths = [
      # Small ripples
      width * 0.05,
      # Tiny ripples
      width * 0.03
    ]

    # Initial waves that will decay
    initial_waves =
      Enum.flat_map(initial_wavelengths, fn wavelength ->
        # Create multiple waves per wavelength with different directions
        for direction <- [0, :math.pi() / 4, :math.pi() / 2, 3 * :math.pi() / 4] do
          create_initial_wave(wavelength, direction, wave_strength)
        end
      end)

    # Persistent wind waves (very small)
    wind_waves =
      Enum.flat_map(wind_wavelengths, fn wavelength ->
        for direction <- [0, :math.pi() / 3, 2 * :math.pi() / 3, :math.pi()] do
          # Much smaller
          create_wind_wave(wavelength, direction, wave_strength * 0.1)
        end
      end)

    initial_waves ++ wind_waves
  end

  # Create a single initial Gerstner wave that will decay over time
  defp create_initial_wave(wavelength, direction, strength_multiplier) do
    # Calculate wave properties using proper dispersion relation
    # Wave number
    k = 2 * :math.pi() / wavelength
    # Deep water dispersion: ω = √(gk)
    frequency = :math.sqrt(9.81 * k)
    # Phase speed = ω/k
    speed = frequency / k

    # Amplitude based on wavelength (longer waves are typically larger)
    # Reduced from 0.012 to 0.006
    base_amplitude = wavelength * 0.006 * strength_multiplier

    # Add some randomness to amplitude and phase
    # 0.5 to 1.0
    amplitude_variation = 0.5 + :rand.uniform() * 0.5
    amplitude = base_amplitude * amplitude_variation

    phase = :rand.uniform() * 2 * :math.pi()

    %Wave{
      amplitude: amplitude,
      wavelength: wavelength,
      direction: direction,
      phase: phase,
      # Speed up waves by 3x for better visibility
      frequency: frequency * 3.0,
      speed: speed * 3.0,
      # Track birth time for decay
      birth_time: :os.system_time(:millisecond),
      # Slow decay for background waves
      decay_rate: 0.98,
      initial_amplitude: amplitude,
      is_wind_wave: false
    }
  end

  # Create a persistent wind wave (very small amplitude)
  defp create_wind_wave(wavelength, direction, strength_multiplier) do
    # Calculate wave properties using proper dispersion relation
    # Wave number
    k = 2 * :math.pi() / wavelength
    # Deep water dispersion: ω = √(gk)
    frequency = :math.sqrt(9.81 * k)
    # Phase speed = ω/k
    speed = frequency / k

    # Very small amplitude for wind waves
    # Reduced from 0.002 to 0.001
    base_amplitude = wavelength * 0.001 * strength_multiplier

    # Add some randomness to amplitude and phase
    # 0.8 to 1.2
    amplitude_variation = 0.8 + :rand.uniform() * 0.4
    amplitude = base_amplitude * amplitude_variation

    phase = :rand.uniform() * 2 * :math.pi()

    %Wave{
      amplitude: amplitude,
      wavelength: wavelength,
      direction: direction,
      phase: phase,
      # Slower than main waves
      frequency: frequency * 2.0,
      speed: speed * 2.0,
      # No decay for wind waves
      birth_time: nil,
      decay_rate: nil,
      initial_amplitude: amplitude,
      is_wind_wave: true
    }
  end

  # Create interaction wave when button is pressed
  defp create_interaction_wave(state, button_number) do
    # Get display info to access panel_to_global_coords
    display_info = Octopus.App.get_display_info()

    panel_width = display_info.panel_width
    panel_height = display_info.panel_height
    panel_count = display_info.num_panels

    if button_number < panel_count do
      case display_info.panel_to_global_coords.(button_number, 0, 0) do
        {panel_x, panel_y} ->
          # Create wave centered at panel
          origin_x = panel_x + trunc(panel_width / 2)

          # Add button flash effect
          button_flash = %{
            panel_number: button_number,
            panel_x: panel_x,
            panel_y: panel_y,
            panel_width: panel_width,
            panel_height: panel_height,
            start_time: :os.system_time(:millisecond),
            # Flash for 300ms
            duration: 300
          }

          # Create multiple waves for broader effect
          interaction_waves = [
            # Main wave - medium wavelength
            %Wave{
              # Reduced from 1.5 to 0.8
              amplitude: state.wave_strength * 0.8,
              # Longer wavelength for broader spread
              wavelength: state.width * 0.25,
              # Will be calculated radially in rendering
              direction: 0,
              phase: 0,
              frequency: :math.sqrt(9.81 * 2 * :math.pi() / (state.width * 0.25)) * 3.0,
              speed: :math.sqrt(9.81 * (state.width * 0.25) / (2 * :math.pi())) * 3.0,
              birth_time: :os.system_time(:millisecond),
              # Faster decay than background
              decay_rate: 0.94,
              initial_amplitude: state.wave_strength * 0.8,
              is_wind_wave: false
            },
            # Secondary wave - longer wavelength for even broader effect
            %Wave{
              # Smaller secondary wave
              amplitude: state.wave_strength * 0.6,
              # Even longer wavelength
              wavelength: state.width * 0.4,
              direction: 0,
              # Phase offset for complexity
              phase: :math.pi() / 4,
              frequency: :math.sqrt(9.81 * 2 * :math.pi() / (state.width * 0.4)) * 3.0,
              speed: :math.sqrt(9.81 * (state.width * 0.4) / (2 * :math.pi())) * 3.0,
              birth_time: :os.system_time(:millisecond),
              # Slower decay for longer persistence
              decay_rate: 0.96,
              initial_amplitude: state.wave_strength * 0.6,
              is_wind_wave: false
            }
          ]

          # Store origin for radial calculation on all waves
          interaction_waves_with_origin =
            Enum.map(interaction_waves, fn wave ->
              wave
              |> Map.put(:origin_x, origin_x)
              |> Map.put(:origin_y, panel_y + trunc(panel_height / 2))
            end)

          %{
            state
            | interaction_waves: interaction_waves_with_origin ++ state.interaction_waves,
              button_flashes: [button_flash | state.button_flashes]
          }

        :invalid_panel ->
          # Logger.error("Ocean: Invalid panel #{button_number}")
          state
      end
    else
      # Logger.debug("Ocean: Button #{button_number} out of range (max: #{panel_count - 1})")
      state
    end
  end

  # Render water using Gerstner wave calculations
  defp render_gerstner_water(state, time, interaction_waves, button_flashes) do
    canvas = Canvas.new(state.width, state.height)

    # Calculate water height and wave energy for each column using Gerstner waves
    water_data =
      for x <- 0..(state.width - 1) do
        water_height =
          calculate_water_height_at_position(x, time, state.background_waves, interaction_waves)

        wave_energy =
          calculate_wave_energy_at_position(x, time, state.background_waves, interaction_waves)

        {water_height, wave_energy}
      end

    # Render the water surface
    Enum.reduce(0..(state.width - 1), canvas, fn x, canvas ->
      {water_height, wave_energy} = Enum.at(water_data, x)
      actual_water_level = state.water_level + water_height

      Enum.reduce(0..(state.height - 1), canvas, fn y, canvas ->
        # Check if this pixel is in a button flash area
        in_button_flash = pixel_in_button_flash?(x, y, button_flashes)

        # Determine if this pixel should show water
        if y >= actual_water_level do
          # Calculate water depth and color intensity
          depth = y - actual_water_level + 1
          max_depth = state.height - state.water_level

          # Create blue gradient - deeper water is darker
          intensity = max(0, min(1, depth / max_depth))

          # Add wave highlights for positive heights (wave peaks)
          wave_highlight = if water_height > 0, do: min(0.4, water_height * 0.1), else: 0
          # Add wave shadows for negative heights (wave troughs)
          wave_shadow = if water_height < 0, do: max(-0.3, water_height * 0.05), else: 0

          # Calculate base colors
          blue_component = trunc(50 + intensity * 150 + wave_highlight * 100 + wave_shadow * 50)
          green_component = trunc(30 + intensity * 100 + wave_highlight * 60 + wave_shadow * 30)
          red_component = trunc(10 + wave_highlight * 40)

          # Apply wave energy as subtle brightness boost - much more conservative
          # Use the simplified activity value
          energy_boost = wave_energy

          # Much more subtle energy visualization
          {blue_boosted, green_boosted, red_boosted} =
            if energy_boost > 0.2 do
              # Only boost colors for significant recent activity
              # Max 30% brighter
              brightness_multiplier = 1.0 + energy_boost * 0.3

              blue_val = trunc(blue_component * brightness_multiplier)
              green_val = trunc(green_component * brightness_multiplier)
              red_val = trunc(red_component * brightness_multiplier)

              {blue_val, green_val, red_val}
            else
              # Normal colors for low/no activity
              {blue_component, green_component, red_component}
            end

          # Log color changes for debugging when there are significant differences
          # if rem(x, 25) == 0 and wave_energy > 0.2 do
          #   Logger.debug(
          #     "Ocean: x=#{x} energy=#{Float.round(wave_energy, 3)}, brightness boost: #{Float.round(1.0 + energy_boost * 0.3, 2)}x"
          #   )
          # end

          color = {
            max(0, min(255, red_boosted)),
            max(0, min(255, green_boosted)),
            max(0, min(255, blue_boosted))
          }

          Canvas.put_pixel(canvas, {x, y}, color)
        else
          # Above water - check for button flash
          if in_button_flash do
            # Flash effect - bright white/blue
            flash_intensity = get_button_flash_intensity(x, y, button_flashes)

            flash_color = {
              trunc(flash_intensity * 100),
              trunc(flash_intensity * 150),
              trunc(flash_intensity * 255)
            }

            Canvas.put_pixel(canvas, {x, y}, flash_color)
          else
            canvas
          end
        end
      end)
    end)
  end

  # Calculate water height at a specific position using Gerstner wave superposition
  defp calculate_water_height_at_position(x, time, background_waves, interaction_waves) do
    # Sum all background waves
    background_height =
      Enum.reduce(background_waves, 0.0, fn wave, acc ->
        acc + calculate_gerstner_wave_height(wave, x, time)
      end)

    # Sum all interaction waves (with decay)
    interaction_height =
      Enum.reduce(interaction_waves, 0.0, fn wave, acc ->
        height = calculate_interaction_wave_height(wave, x, time)
        acc + height
      end)

    total_height = background_height + interaction_height

    # Clamp the wave height to ensure water level stays within bounds
    # More conservative clamping to prevent black panels
    # Smaller minimum drop - ensures plenty of water is always visible
    min_wave_height = -8.0
    # Slightly reduced maximum rise
    max_wave_height = 20.0
    clamped_height = max(min_wave_height, min(max_wave_height, total_height))

    clamped_height
  end

  # Calculate height contribution from a single Gerstner wave
  defp calculate_gerstner_wave_height(wave, x, time) do
    # Apply decay if this is a decaying background wave
    current_amplitude =
      if wave.birth_time && !wave.is_wind_wave do
        age_seconds = (:os.system_time(:millisecond) - wave.birth_time) / 1000.0

        # Decay over 10-15 seconds to very small amplitude
        decay_factor = :math.pow(wave.decay_rate, age_seconds * 0.8)

        # Don't let it go completely to zero, leave some minimal movement
        # 5% of original
        min_amplitude = wave.initial_amplitude * 0.05
        max(min_amplitude, wave.amplitude * decay_factor)
      else
        # Wind waves or interaction waves use their current amplitude
        wave.amplitude
      end

    # Gerstner wave equation: η = A * cos(kx - ωt + φ)
    k = 2 * :math.pi() / wave.wavelength
    phase = k * x * :math.cos(wave.direction) - wave.frequency * time + wave.phase

    current_amplitude * :math.cos(phase)
  end

  # Calculate height contribution from interaction wave (radial with decay)
  defp calculate_interaction_wave_height(wave, x, time) do
    if wave.birth_time do
      age_seconds = (:os.system_time(:millisecond) - wave.birth_time) / 1000.0

      # Calculate distance from origin
      distance = abs(x - wave.origin_x)

      # Calculate radial wave
      k = 2 * :math.pi() / wave.wavelength
      phase = k * distance - wave.frequency * time

      # Apply time decay
      time_decay = :math.pow(wave.decay_rate, age_seconds * 2.0)

      # Apply distance decay (waves get weaker as they spread)
      distance_decay = 1.0 / (1.0 + distance * 0.01)

      wave.amplitude * time_decay * distance_decay * :math.cos(phase)
    else
      0.0
    end
  end

  # Calculate wave energy at a specific position - focus on recent interaction activity
  defp calculate_wave_energy_at_position(x, _time, _background_waves, interaction_waves) do
    # Skip background waves entirely for energy visualization - they're too uniform
    # Focus only on interaction waves (button presses) for energy differences

    interaction_activity =
      Enum.reduce(interaction_waves, 0.0, fn wave, acc ->
        if wave.birth_time do
          age_seconds = (:os.system_time(:millisecond) - wave.birth_time) / 1000.0
          distance = abs(x - wave.origin_x)

          # Only count recent waves (first 3 seconds) for energy visualization
          if age_seconds < 3.0 do
            # Simple distance-based energy that's easy to see
            # Energy visible within 50 pixels
            max_distance = 50.0

            if distance < max_distance do
              # Linear falloff from button press location
              distance_factor = 1.0 - distance / max_distance
              # Time factor - strongest in first second, fades over 3 seconds
              time_factor = 1.0 - age_seconds / 3.0

              wave_energy = wave.initial_amplitude * distance_factor * time_factor
              acc + wave_energy
            else
              acc
            end
          else
            acc
          end
        else
          acc
        end
      end)

    # Simple scaling - no complex math
    scaled_activity = min(1.0, interaction_activity * 0.5)

    # Log energy values for debugging
    # if rem(x, 25) == 0 and scaled_activity > 0.1 do
    #   Logger.debug("Ocean: x=#{x} interaction_activity=#{Float.round(scaled_activity, 3)}")
    # end

    scaled_activity
  end

  # Check if a pixel is within any button flash area
  defp pixel_in_button_flash?(x, y, button_flashes) do
    Enum.any?(button_flashes, fn flash ->
      x >= flash.panel_x && x < flash.panel_x + flash.panel_width &&
        y >= flash.panel_y && y < flash.panel_y + flash.panel_height
    end)
  end

  # Get button flash intensity at a specific pixel
  defp get_button_flash_intensity(x, y, button_flashes) do
    current_time = :os.system_time(:millisecond)

    Enum.reduce(button_flashes, 0.0, fn flash, acc ->
      if x >= flash.panel_x && x < flash.panel_x + flash.panel_width &&
           y >= flash.panel_y && y < flash.panel_y + flash.panel_height do
        # Calculate fade-out intensity
        age_ms = current_time - flash.start_time
        # 0.0 to 1.0
        progress = age_ms / flash.duration
        # Fade from 1.0 to 0.0
        intensity = max(0.0, 1.0 - progress)

        max(acc, intensity)
      else
        acc
      end
    end)
  end

  # Cleanup when app terminates
  def terminate(_reason, %State{} = state) do
    # Logger.info("Ocean: App terminating (reason: \\#{inspect(reason)})")

    # Cancel inactivity timer if it exists
    if state.inactivity_timer_ref do
      :timer.cancel(state.inactivity_timer_ref)
    end

    :ok
  end

  defp apply_config(%State{} = state, config) do
    wave_strength = Map.get(config, :wave_strength, state.wave_strength || 1.0)
    damping = Map.get(config, :damping, state.damping || 0.95)
    water_level_ratio = Map.get(config, :water_level, state.water_level_ratio || 0.6)
    water_level = state.height * water_level_ratio

    strength_changed? = wave_strength != state.wave_strength

    background_waves =
      if strength_changed? or is_nil(state.background_waves) do
        generate_background_waves(state.width, wave_strength)
      else
        state.background_waves
      end

    %State{
      state
      | wave_strength: wave_strength,
        damping: damping,
        water_level_ratio: water_level_ratio,
        water_level: water_level,
        background_waves: background_waves
    }
  end

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
end
