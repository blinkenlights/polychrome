defmodule Octopus.Hardware.Controllers do
  @moduledoc """
  Catalog of Polychrome Blinkenled controllers.
  """

  alias Octopus.Hardware.Controller

  @controllers [
    {:polychrome_panel_1, 1, "blinkenleds-1.local", "cc:db:a7:46:03:03"},
    {:polychrome_panel_2, 2, "blinkenleds-2.local", "cc:db:a7:46:03:13"},
    {:polychrome_panel_3, 3, "blinkenleds-3.local", "cc:db:a7:51:eb:ab"},
    {:polychrome_panel_4, 4, "blinkenleds-4.local", "cc:db:a7:50:c6:7f"},
    {:polychrome_panel_5, 5, "blinkenleds-5.local", "cc:db:a7:45:fe:f7"},
    {:polychrome_panel_6, 6, "blinkenleds-6.local", "cc:db:a7:52:16:03"},
    {:polychrome_panel_7, 7, "blinkenleds-7.local", "cc:db:a7:45:f5:3b"},
    {:polychrome_panel_8, 8, "blinkenleds-8.local", "cc:db:a7:45:f5:93"},
    {:polychrome_panel_9, 9, "blinkenleds-9.local", "cc:db:a7:52:f7:fb"},
    {:polychrome_panel_10, 10, "blinkenleds-10.local", "cc:db:a7:50:df:5b"},
    # SKIP_LEDS firmware env (physical strip gaps); still 64 px over UDP
    {:polychrome_panel_11, 11, "blinkenleds-11.local", "14:2b:2f:e5:70:ab"},
    {:polychrome_panel_12, 12, "blinkenleds-12.local", "94:54:c5:ff:dc:73"},
    {:polychrome_panel_prototype, 1, "blinkenleds-prototype.local", "54:43:b2:b6:6e:57"}
  ]

  @doc """
  Returns all catalog controllers as a map of controller id => `%Controller{}`.
  """
  @spec all() :: %{atom() => Controller.t()}
  def all do
    Map.new(@controllers, fn {id, index, hostname, mac} ->
      {id, controller(id, index, hostname, mac)}
    end)
  end

  @doc """
  Returns all controller ids in catalog definition order.
  """
  @spec ids() :: [atom()]
  def ids, do: for({id, _, _, _} <- @controllers, do: id)

  defp controller(id, index, hostname, mac) do
    %Controller{
      id: id,
      firmware_panel_index: index,
      hostname: hostname,
      mac: mac,
      max_pixel_count: 64,
      firmware_matrix: {8, 8},
      firmware_wire_map: :serpentine_8x8_bottom_left,
      firmware_version: nil
    }
  end
end
