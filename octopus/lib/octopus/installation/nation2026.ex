defmodule Octopus.Installation.Nation2026 do
  use Octopus.Installation,
    arrangement: :circular,
    circular: [
      ring_radius_m: 10.0,
      north_panel: 10,
      platform_radius_m: 2.25,
      panel_bottom_m: 0.4
    ],
    panel_type: :polychrome,
    panels: [
      [controller: :polychrome_01, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_02, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_03, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_04, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_05, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_06, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_07, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_08, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_09, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_10, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_11, wiring: :serpentine_horizontal_bottom_left],
      [controller: :polychrome_12, wiring: :serpentine_horizontal_bottom_left]
    ],
    panel_layout: {8, 8},
    num_buttons: 0,
    num_joysticks: 0,
    panel_gap: 18,
    global_speed: 1.0,
    location: {52.684273, 12.959300},
    auto_brightness: false,
    radar: [
      defaults: [
        moving_decisecs: 110,
        static_decisecs: 100,
        exit_decisecs: 5,
        height_cm: 500,
        range_cm: 500,
        x_pos_cm: 500,
        x_neg_cm: -500,
        y_pos_cm: 500,
        y_neg_cm: -500
      ],
      layout: [
        type: :radial,
        sensors: [
          :a,
          :b,
          [id: :c, rotation_deg: 323],
          :d,
          :e,
          :f
        ],
        start_angle_deg: 150,
        distance_cm: 300
      ],
      panel_activity: [
        sensitivity: 1.0,
        adaptive: true,
        release_tau: 5.0
      ]
    ],
    network_config: [
      mode: :broadcast,
      broadcast_ip: :auto,
      send_in_dev: false
    ],
    simulator_layouts: [
      [
        name: "Generic Development View",
        mode: "generic",
        pixel_size: {12, 12}
      ],
      [
        name: "Streifen (abgewickelt)",
        mode: "strip",
        pixel_size: {8, 8},
        panel_gap: 1
      ],
      [
        name: "Nation 2026",
        mode: "image",
        background_image: "/images/nation2025-background.webp",
        pixel_image: "/images/nation2025-overlay.webp",
        image_size: {3463, 1469},
        pixel_size: {8, 8},
        offset_x: 600,
        offset_y: 1100,
        spacing: 128
      ]
    ]
end
