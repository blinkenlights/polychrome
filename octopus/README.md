# Octopus

You can reach a hosted version here: https://polychrome.fly.dev

## Local setup
### Dependencies
On Linux you need:
- build-essential (on Ubuntu - so generally the standard development framework)
- elixir
- elixir-os-mon
- erlang-dev
- erlang-xmerl
- rust

### Installation
- Clone repository `git clone https://github.com/blinkenlights/polychrome`
- Change directory `cd polychrome/octopus`
- Run `mix setup` to install and setup dependencies
- When running for the fist time create and migrate the database by running `mix ecto.create` and then `mix ecto.migrate`
- Start the server with `iex -S mix phx.server`

Octopus should now be reachable on [`localhost:4000`](http://localhost:4000).

To auto-start an app on boot (runtime, no recompile):

```bash
BOOT_APP=GravityMask iex -S mix phx.server
# optional mode preset:
BOOT_APP=GravityMask BOOT_APP_MODE=gravitymask:mask iex -S mix phx.server
```

`BOOT_APP` accepts a short Apps name (`GravityMask`) or a full module
(`Octopus.Apps.GravityMask`). `OCTOPUS_BOOT_APP` / `OCTOPUS_BOOT_APP_MODE`
are aliases.

Start the "UDP Server" app to receive external frames on UDP port 2342

### Dual Octopus instances (Pixie + Pixie2 / Woodstock on one device)

The `:pixie` catalog controller exposes two UDP buses (`ports: 2`):

| Installation | Slot | Device UDP | Typical local bind | Layout |
|--------------|------|------------|--------------------|--------|
| `Octopus.Installation.Pixie` | `port: 1` | 1337 | 4422 (default) | 8×8 |
| `Octopus.Installation.Pixie2` | `port: 2` | 1338 | 4423 | 8×8 |
| `Octopus.Installation.Woodstock` | `port: 2` | 1338 | 4423 | 2×32 |

Run two processes with distinct installation modules and local reply ports:

```bash
# Terminal 1 — Pixie (GPIO 16 / UDP 1337)
INSTALLATION_MODULE=Octopus.Installation.Pixie \
  mix phx.server

# Terminal 2 — Pixie2 (GPIO 3 / UDP 1338); use another HTTP port if needed
INSTALLATION_MODULE=Octopus.Installation.Pixie2 \
  FIRMWARE_BROADCASTER_LOCAL_PORT=4423 \
  PORT=4001 \
  mix phx.server
```

`FIRMWARE_BROADCASTER_LOCAL_PORT` must be wired in config (see below) so both GenServers can bind. Firmware replies to whichever source port sent pixel data on that bus — it does not hardcode Octopus ports.

Set the local port via runtime config, for example in `config/runtime.exs` or `config/dev.exs`:

```elixir
if local = System.get_env("FIRMWARE_BROADCASTER_LOCAL_PORT") do
  config :octopus, :firmware_broadcaster_local_port, String.to_integer(local)
end
```

### Updating Protobuf

`make protbuf_generate` updates based on the protobuf schema in `../protobuf/schema.proto`

Needs `protoc`
* `brew install protobuf` on mac
* `apt install -y protobuf-compiler` on linux
