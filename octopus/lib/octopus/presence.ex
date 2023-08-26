defmodule Octopus.Presence do
  use Phoenix.Presence,
    otp_app: :octopus,
    pubsub_server: Octopus.PubSub
end
