defmodule Octopus.Hardware.Controllers do
  @moduledoc """
  Catalog of Polychrome Blinkenled controllers.
  """

  alias Octopus.Hardware.Controller

  # {id, firmware_panel_index, hostname, mac, ports}
  @controllers [
    {:polychrome_01, 1, "blinkenleds-1.local", "cc:db:a7:46:03:03", 1},
    {:polychrome_02, 2, "blinkenleds-2.local", "cc:db:a7:46:03:13", 1},
    {:polychrome_03, 3, "blinkenleds-3.local", "cc:db:a7:51:eb:ab", 1},
    {:polychrome_04, 4, "blinkenleds-4.local", "cc:db:a7:50:c6:7f", 1},
    {:polychrome_05, 5, "blinkenleds-5.local", "cc:db:a7:45:fe:f7", 1},
    {:polychrome_06, 6, "blinkenleds-6.local", "cc:db:a7:52:16:03", 1},
    {:polychrome_07, 7, "blinkenleds-7.local", "cc:db:a7:45:f5:3b", 1},
    {:polychrome_08, 8, "blinkenleds-8.local", "cc:db:a7:45:f5:93", 1},
    {:polychrome_09, 9, "blinkenleds-9.local", "cc:db:a7:52:f7:fb", 1},
    {:polychrome_10, 10, "blinkenleds-10.local", "cc:db:a7:50:df:5b", 1},
    # SKIP_LEDS firmware env (physical strip gaps); still 64 px over UDP
    {:polychrome_11, 11, "blinkenleds-11.local", "14:2b:2f:e5:70:ab", 1},
    {:polychrome_12, 12, "blinkenleds-12.local", "94:54:c5:ff:dc:73", 1},
    {:pixie, 1, "blinkenleds-prototype.local", "54:43:b2:b6:6e:57", 2}
  ]

  @doc """
  Returns all catalog controllers as a map of controller id => `%Controller{}`.
  """
  @spec all() :: %{atom() => Controller.t()}
  def all do
    Map.new(@controllers, fn {id, index, hostname, mac, ports} ->
      {id, controller(id, index, hostname, mac, ports)}
    end)
  end

  @doc """
  Returns all controller ids in catalog definition order.
  """
  @spec ids() :: [atom()]
  def ids, do: for({id, _, _, _, _} <- @controllers, do: id)

  defp controller(id, index, hostname, mac, ports) do
    %Controller{
      id: id,
      firmware_panel_index: index,
      hostname: hostname,
      mac: mac,
      ports: ports,
      udp_port_base: 1337,
      max_pixel_count: 64,
      firmware_matrix: {8, 8},
      firmware_wire_map: :serpentine_horizontal_bottom_left,
      firmware_version: nil
    }
  end
end
