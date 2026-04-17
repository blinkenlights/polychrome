defmodule Octopus.Params.Sim3d do
  use Octopus.Params, prefix: :sim_3d

  def topic, do: "sim_3d"

  def diameter, do: param(:diameter, 18.0)
  def move, do: param(:move, [0.0, 0.0])
  def position, do: param(:position, [0.0, 0.0])
  def height, do: param(:height, 0.4)
  def pole_diameter, do: param(:pole_diameter, 0.15)
  def foot_diameter, do: param(:foot_diameter, 0.3)
  def button_diameter, do: param(:button_diameter, 5.0)
  def radar_count, do: param(:radar_count, 6)

  def handle_param("diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:diameter, value})
  end

  def handle_param("move", [x, y]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:move, [x, y]})
  end

  def handle_param("position", [x, y]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:position, [x, y]})
  end

  def handle_param("height", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:height, value})
  end

  def handle_param("pole_diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:pole_diameter, value})
  end

  def handle_param("foot_diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:foot_diameter, value})
  end

  def handle_param("button_diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:button_diameter, value})
  end

  def handle_param("radar_count", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:radar_count, value})
  end
end
