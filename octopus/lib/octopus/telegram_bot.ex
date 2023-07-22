defmodule Octopus.TelegramBot do
  @moduledoc """
  Simple interface to a telegram bot. Use the TELEGRAM_BOT_SECRET environment variable
  to pass a Telegram bot token to the library. The library connects to Telegram and waits
  for commands. Any received command is announced via PubSub and can be consumed by any
  module subscribing to it.
  """
  use GenServer
  require Logger

  @topic "polychrome_bot_update"
  defstruct [:bot_key, :me, :last_seen]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @impl GenServer
  def init(opts) do
    {key, _opts} = Keyword.pop!(opts, :bot_key)

    case Telegram.Api.request(key, "getMe") do
      {:ok, me} ->
        Logger.info("Bot successfully self-identified: #{me["username"]}")

        state = %__MODULE__{
          bot_key: key,
          me: me,
          last_seen: -2
        }

        next_loop()

        {:ok, state}

      error ->
        Logger.error("Bot failed to self-identify: #{inspect(error)}")
        :error
    end
  end

  @impl GenServer
  def handle_info(:check, %{bot_key: key, last_seen: last_seen} = state) do
    state =
      key
      |> Telegram.Api.request("getUpdates", offset: last_seen + 1, timeout: 30)
      |> case do
        # Empty, typically a timeout. State returned unchanged.
        {:ok, []} ->
          next_loop()
          state

        # A response with content, exciting!
        {:ok, updates} ->
          # Process our updates and return the latest update ID
          last_seen = handle_updates(updates, last_seen)

          # Update the last_seen state so we only get new updates on the
          # next check
          next_loop()
          %{state | last_seen: last_seen}

        {:error, reason} ->
          Logger.warning("Bot: Can't get updates: #{reason}")
          state
      end

    {:noreply, state}
  end

  defp handle_updates(updates, last_seen) do
    updates
    # Process our updates
    |> Enum.map(fn update ->
      Logger.debug("Update received: #{inspect(update)}")
      # Offload the updates to whoever they may concern
      broadcast(update)

      # Return the update ID so we can boil it down to a new last_seen
      update["update_id"]
    end)
    # Get the highest seen id from the new updates or fall back to last_seen
    |> Enum.max(fn -> last_seen end)
  end

  def topic, do: @topic

  defp broadcast(update) do
    # Send each update to a topic for others to listen to.
    Phoenix.PubSub.broadcast!(Octopus.PubSub, @topic, {:bot_update, update})
  end

  defp next_loop do
    Process.send_after(self(), :check, 0)
  end
end
