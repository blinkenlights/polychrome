defmodule Octopus.Apps.Photo do
  use Octopus.App

  alias Octopus.{Canvas, Image}
  alias Octopus.Protobuf.InputEvent

  @photo "monkey"
  @fps 60

  defmodule State do
    defstruct [:photo, :time]
  end

  def name(), do: "Photo Scroller"

  def init(_args) do
    photo = Image.load(@photo)

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, %State{photo: photo, time: 0}}
  end

  def handle_info(:tick, %State{} = state) do
    canvas = Canvas.new((8+16)*10, 8)

    dx = trunc((:math.sin(state.time)+1)/2*(state.photo.width-canvas.width))
    dy = trunc((:math.sin(state.time/2)+1)/2*(state.photo.height-canvas.height))

    pixel_coords = for x <- 0..(canvas.width-1), y <- 0..(canvas.height-1), do: {x, y}

    canvas = Enum.reduce(pixel_coords, canvas, fn {x, y}, canvas ->
      color = Canvas.get_pixel(state.photo, {x+dx, y+dy})
      Canvas.put_pixel(canvas, {x, y}, color)
    end)

    canvas
      |> Canvas.to_frame(drop: true)
      |> send_frame()

    {:noreply, %State{state | time: state.time + 1/@fps}}
  end
end
