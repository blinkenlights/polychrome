# Octopus

You can reach a hosted version here: https://remote-octopus.fly.dev

## Local setup

- Install elixir: https://elixir-lang.org/install.html
- Run `mix setup` to install and setup dependencies
- Start the server with `iex -S mix phx.server`

Octopus should now be reachable on [`localhost:4000`](http://localhost:4000). 

Start the "UDP Server" app to receive external frames on UDP port 2342


### Updating Protobuf

`make protbuf_generate` updates based on the protobuf schema in `../protobuf/schema.proto`

Needs `protoc`
* `brew install protobuf` on mac
* `apt install -y protobuf-compiler` on linux