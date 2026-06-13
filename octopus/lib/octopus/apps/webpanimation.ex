defmodule Octopus.Apps.Webpanimation do
  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.WebP

  defmodule State do
    defstruct [:frames, :animation, :width, :height, :loop]
  end

  def name(), do: "Webp Animation"

  def compatible?() do
    # Check if we have any WebP animations that would work well with current installation
    installation = Octopus.App.get_installation_info()
    adjacent_width = installation.panel_count * installation.panel_width
    gapped_width = adjacent_width + (installation.panel_count - 1) * installation.panel_gap

    webp_dir = Path.join([:code.priv_dir(:octopus), "webp"])

    if File.exists?(webp_dir) do
      webp_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".webp"))
      |> Enum.any?(fn filename ->
        path = Path.join(webp_dir, filename)

        case WebP.decode_animation(path) do
          %{size: {width, _height}} ->
            # Animation is compatible if it's designed for the current installation
            # For Nation2025 (272px gapped), we need animations close to that size
            # For Nation2024 (242px gapped), we need animations close to that size
            # Small animations (8px, 18px) work but provide poor experience

            cond do
              # Good fit for gapped layout (within 30px of target)
              abs(width - gapped_width) <= 30 -> true
              # Good fit for adjacent layout (uses most of the space)
              width >= adjacent_width * 0.8 and width <= adjacent_width -> true
              # Animation is too small or wrong size for good experience
              true -> false
            end

          _ ->
            false
        end
      end)
    else
      false
    end
  end

  def config_schema() do
    %{
      animation: {"Animation", :string, %{default: "mario-run"}},
      loop: {"Loop", :boolean, %{default: true}}
    }
  end

  def app_init(%{animation: animation, loop: loop}) do
    state =
      %State{frames: [], animation: nil, width: 0, height: 0, loop: loop}
      |> load_animation(animation)

    # Configure layout based on animation width
    # Width >= 242 indicates animations designed for gapped panels
    layout = if state.width >= 242, do: :gapped_panels, else: :adjacent_panels
    Octopus.App.configure_display(layout: layout)

    send(self(), :tick)

    {:ok, state}
  end

  def get_config(%State{animation: animation, loop: loop}) do
    %{animation: animation, loop: loop}
  end

  defp load_animation(%State{} = state, animation) do
    path = Path.join([:code.priv_dir(:octopus), "webp", animation <> ".webp"])

    if File.exists?(path) do
      decoded_animation = WebP.decode_animation(path)
      {width, height} = decoded_animation.size
      frames = convert_timestamps_to_duration(decoded_animation.frames)

      %State{state | animation: animation, frames: frames, width: width, height: height}
    else
      state
    end
  end

  def handle_config(%{animation: animation, loop: loop}, %State{} = state) do
    state =
      if state.animation != animation do
        send(self(), :tick)
        new_state = load_animation(state, animation)

        # Reconfigure layout if animation width changed
        layout = if new_state.width >= 242, do: :gapped_panels, else: :adjacent_panels
        Octopus.App.configure_display(layout: layout)

        new_state
      else
        state
      end

    {:noreply, %State{state | loop: loop}}
  end

  def handle_info(:tick, %State{frames: [], loop: false}) do
    {:stop, :normal, nil}
  end

  def handle_info(:tick, %State{frames: [], loop: true} = state) do
    state = load_animation(state, state.animation)
    send(self(), :tick)
    {:noreply, state}
  end

  def handle_info(
        :tick,
        %State{frames: [animation_info | more_frames], width: width, height: height} = state
      ) do
    {pixels, duration} = animation_info

    canvas = Canvas.new(width, height)
    image = Enum.chunk_every(pixels, width)

    {canvas, _} =
      Enum.reduce(image, {canvas, 0}, fn row, {canvas, y} ->
        {canvas, _, y} =
          Enum.reduce(row, {canvas, 0, y}, fn [r, g, b], {canvas, x, y} ->
            canvas =
              Canvas.put_pixel(
                canvas,
                {x, y},
                {r, g, b}
              )

            {canvas, x + 1, y}
          end)

        {canvas, y + 1}
      end)

    # Use new unified display API instead of conditional Canvas.to_frame(drop: width >= 242)
    Octopus.App.update_display(canvas)

    Process.send_after(self(), :tick, duration)
    {:noreply, %{state | frames: more_frames}}
  end

  defp convert_timestamps_to_duration(frames) do
    {new_frames, _} =
      Enum.reduce(frames, {[], 0}, fn {pixels, old_time_stamp}, {new_frames, last_time_stamp} ->
        {new_frames ++ [{pixels, old_time_stamp - last_time_stamp}], old_time_stamp}
      end)

    new_frames
  end
end
