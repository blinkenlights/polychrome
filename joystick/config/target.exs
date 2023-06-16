import Config

# Use Ringlogger as the logger backend and remove :console.
# See https://hexdocs.pm/ring_logger/readme.html for more information on
# configuring ring_logger.

config :logger, backends: [RingLogger]

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.
config :nerves,
  erlinit: [
    hostname_pattern: "joystick"
  ]

# Advance the system clock on devices without real-time clocks.
config :nerves, :erlinit, update_clock: true

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://hexdocs.pm/nerves_ssh/readme.html for general SSH configuration
# * See https://hexdocs.pm/ssh_subsystem_fwup/readme.html for firmware updates

config :nerves_ssh,
  authorized_keys: [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFk68ujMEgPVglDNnxqrht/0piGwofQy4GmPjgq4CvUV"
  ]

# Configure the network using vintage_net
# See https://github.com/nerves-networking/vintage_net for more information
config :vintage_net,
  regulatory_domain: "DE",
  config: [
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }}
  ],
  additional_name_servers: [{127, 0, 0, 53}]

config :mdns_lite,
  hosts: [:hostname, "joystick"],
  ttl: 120,
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    }
  ],
  dns_bridge_enabled: true,
  dns_bridge_ip: {127, 0, 0, 53},
  dns_bridge_port: 53,
  dns_bridge_recursive: true

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
