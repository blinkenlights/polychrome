defmodule Octopus.Apps.Senso do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Protobuf.{SynthFrame, AudioFrame, SynthConfig, SynthAdsrConfig}
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  @first_squence_len 3
  @state_time_delta 100
  @time_between_elements_ms 500

  @synth_config %SynthConfig{
    wave_form: :SQUARE,
    gain: 1,
    adsr_config: %SynthAdsrConfig{
      attack: 0.01,
      decay: 0,
      sustain: 1,
      release: 0.2
    }
  }

  defmodule State do
    defstruct expected_sequence: [],
              index: 0,
              successes: 0,
              input_blocked: true,
              display_info: nil
  end

  def name(), do: "Senso"

  def compatible?() do
    # Senso requires exactly one button per panel for proper gameplay
    installation_info = Octopus.App.get_installation_info()

    installation_info.num_buttons == installation_info.panel_count
  end

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout
    Octopus.App.configure_display(layout: :adjacent_panels)
    Octopus.App.subscribe_to_button_events()

    # Get display info once and store it
    display_info = Octopus.App.get_display_info()

    state = %State{
      expected_sequence: generate_sequence(@first_squence_len, display_info.num_panels),
      index: 0,
      successes: 0,
      input_blocked: true,
      display_info: display_info
    }

    send(self(), :run)

    {:ok, state}
  end

  defp generate_sequence(len, panel_count) do
    for _ <- 1..len, do: Enum.random(1..panel_count)
  end

  def handle_info(:run, %State{expected_sequence: expected_sequence, index: index} = state)
      when index < length(expected_sequence) do
    window = Enum.at(expected_sequence, index)

    # Calculate panel position dynamically
    panel_width = state.display_info.panel_width
    panel_height = state.display_info.panel_height
    top_left = {(window - 1) * panel_width, 0}
    bottom_right = {elem(top_left, 0) + panel_width - 1, panel_height - 1}

    Canvas.new(state.display_info.width, state.display_info.height)
    |> Canvas.fill_rect(top_left, bottom_right, get_color(window, state.display_info.num_panels))
    |> Octopus.App.update_display()

    %SynthFrame{
      event_type: :NOTE_ON,
      channel: window,
      note: 60 + window - 1,
      config: @synth_config,
      duration_ms: @time_between_elements_ms,
      velocity: 1
    }
    |> send_synth_event()

    :timer.sleep(@time_between_elements_ms)

    Canvas.new(state.display_info.width, state.display_info.height)
    |> Octopus.App.update_display()

    %SynthFrame{
      event_type: :NOTE_OFF,
      channel: window,
      note: 60 + window - 1
    }
    |> send_synth_event()

    :timer.sleep((@time_between_elements_ms / 2) |> trunc())

    send(self(), :run)
    {:noreply, %State{state | index: state.index + 1, input_blocked: true}}
  end

  ## finished playing sequence
  def handle_info(:run, %State{} = state) do
    {:noreply, %State{state | index: 0, input_blocked: false}}
  end

  def handle_info(:reset, state) do
    new_state = %State{
      expected_sequence: generate_sequence(@first_squence_len, state.display_info.num_panels),
      index: 0,
      successes: 0,
      input_blocked: true,
      display_info: state.display_info
    }

    send(self(), :run)

    {:noreply, new_state}
  end

  def handle_info(:success, %State{} = state) do
    new_state = %State{
      expected_sequence:
        state.expected_sequence ++ generate_sequence(1, state.display_info.num_panels),
      index: 0,
      successes: state.successes + 1,
      input_blocked: true,
      display_info: state.display_info
    }

    :timer.sleep(@time_between_elements_ms)

    send(self(), :run)

    {:noreply, new_state}
  end

  def handle_event(_input_event, %State{input_blocked: true} = state) do
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: button},
        %State{} = state
      )
      when button >= 1 and button <= state.display_info.num_panels do
    btn_num = button

    # Calculate panel position dynamically
    panel_width = state.display_info.panel_width
    panel_height = state.display_info.panel_height
    top_left = {(btn_num - 1) * panel_width, 0}
    bottom_right = {elem(top_left, 0) + panel_width - 1, panel_height - 1}

    Canvas.new(state.display_info.width, state.display_info.height)
    |> Canvas.fill_rect(
      top_left,
      bottom_right,
      get_color(btn_num, state.display_info.num_panels)
    )
    |> Octopus.App.update_display()

    %SynthFrame{
      event_type: :NOTE_ON,
      channel: btn_num,
      note: 60 + btn_num - 1,
      config: @synth_config,
      duration_ms: 1000,
      velocity: 1
    }
    |> send_synth_event()

    {:noreply, state}
  end

  def handle_event(%InputEvent{type: :button, action: :release, button: button}, %State{} = state)
      when button >= 1 and button <= state.display_info.num_panels do
    btn_num = button

    # Calculate panel position dynamically
    panel_width = state.display_info.panel_width
    panel_height = state.display_info.panel_height
    top_left = {(btn_num - 1) * panel_width, 0}
    bottom_right = {elem(top_left, 0) + panel_width - 1, panel_height - 1}

    Canvas.new(state.display_info.width, state.display_info.height)
    |> Canvas.clear_rect(top_left, bottom_right)
    |> Octopus.App.update_display()

    %SynthFrame{
      event_type: :NOTE_OFF,
      channel: btn_num,
      note: 60 + btn_num - 1
    }
    |> send_synth_event()

    success = btn_num == Enum.at(state.expected_sequence, state.index)

    increment =
      if !success do
        display_fail(state.display_info)
        send(self(), :reset)
        0
      else
        1
      end

    finished = state.index + increment >= length(state.expected_sequence)

    if finished do
      display_success(state.display_info)
      send(self(), :success)
    end

    block_input = finished || !success

    {:noreply, %State{state | index: state.index + increment, input_blocked: block_input}}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, %State{} = state) do
    Enum.map(1..state.display_info.num_panels, fn channel ->
      %SynthFrame{
        event_type: :CONFIG,
        channel: channel,
        note: 60,
        config: @synth_config,
        duration_ms: 10
      }
      |> send_synth_event()
    end)

    send(self(), :run)
    {:noreply, %State{state | input_blocked: true}}
  end

  def handle_event(_event, %State{} = state) do
    {:noreply, state}
  end

  defp get_color(num, panel_count) do
    # Use dynamic color calculation based on actual panel count
    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSV.new((num / panel_count * 100) |> trunc(), 100, 100)
      |> Chameleon.convert(Chameleon.RGB)

    {r, g, b}
  end

  def display_fail(display_info) do
    :timer.sleep(200)

    %AudioFrame{
      uri: "file://corrosion15.wav",
      channel: 5
    }
    |> send_audio_event()

    canvas = Canvas.new(display_info.width, display_info.height)

    canvas
    |> Canvas.fill_rect({0, 0}, {display_info.width - 1, display_info.height - 1}, {255, 0, 0})
    |> Octopus.App.update_display()

    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Octopus.App.update_display()
    :timer.sleep(@state_time_delta)

    canvas
    |> Canvas.fill_rect({0, 0}, {display_info.width - 1, display_info.height - 1}, {255, 0, 0})
    |> Octopus.App.update_display()

    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Octopus.App.update_display()
    :timer.sleep((@time_between_elements_ms / 2) |> trunc())
  end

  def display_success(display_info) do
    :timer.sleep(200)

    %AudioFrame{
      uri: "file://corrosion14.wav",
      channel: 5
    }
    |> send_audio_event()

    canvas = Canvas.new(display_info.width, display_info.height)

    canvas
    |> Canvas.fill_rect({0, 0}, {display_info.width - 1, display_info.height - 1}, {0, 255, 0})
    |> Octopus.App.update_display()

    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Octopus.App.update_display()
    :timer.sleep(@state_time_delta)

    canvas
    |> Canvas.fill_rect({0, 0}, {display_info.width - 1, display_info.height - 1}, {0, 255, 0})
    |> Octopus.App.update_display()

    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Octopus.App.update_display()
    :timer.sleep((@time_between_elements_ms / 2) |> trunc())
  end
end
