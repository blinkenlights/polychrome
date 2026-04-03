defmodule Octopus.TelegramBot do
  @moduledoc """
  Simple interface to a Telegram bot. Use the `TELEGRAM_BOT_SECRET` environment variable
  to pass a bot token. This module calls the Telegram Bot API with Req, long-polls for
  updates, and broadcasts each update on PubSub for subscribers.
  """
  use GenServer
  require Logger

  @connection_attempt_timeout 60_000
  @api_base "https://api.telegram.org"

  @topic "polychrome_bot_update"
  defstruct [:bot_key, :me, :last_seen]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @impl GenServer
  def init(opts) do
    {:ok, opts, {:continue, :init}}
  end

  @impl GenServer
  def handle_continue(:init, opts) do
    {key, _opts} = Keyword.pop!(opts, :bot_key)

    case api_request(key, "getMe", %{}) do
      {:ok, me} ->
        Logger.info("Bot successfully self-identified: #{me["username"]}")

        state = %__MODULE__{
          bot_key: key,
          me: me,
          last_seen: -2
        }

        next_loop()

        {:noreply, state}

      error ->
        Logger.error("Bot failed to self-identify: #{inspect(error)}")
        :timer.sleep(@connection_attempt_timeout)
        {:noreply, opts, {:continue, :init}}
    end
  end

  @impl GenServer
  def handle_info(:check, %{bot_key: key, last_seen: last_seen} = state) do
    state =
      api_request(key, "getUpdates", %{
        offset: last_seen + 1,
        timeout: 30
      })
      |> case do
        {:ok, []} ->
          next_loop()
          state

        {:ok, updates} ->
          last_seen = handle_updates(updates, last_seen)
          next_loop()
          %{state | last_seen: last_seen}

        {:error, reason} ->
          Logger.warning("Bot: Can't get updates: #{reason}")
          next_loop()
          state
      end

    {:noreply, state}
  end

  defp handle_updates(updates, last_seen) do
    updates
    |> Enum.map(fn update ->
      Logger.debug("Update received: #{inspect(update)}")
      broadcast(update)
      update["update_id"]
    end)
    |> Enum.max(fn -> last_seen end)
  end

  def topic, do: @topic

  defp broadcast(update) do
    Phoenix.PubSub.broadcast!(Octopus.PubSub, @topic, {:bot_update, update})
  end

  defp next_loop do
    Process.send_after(self(), :check, 0)
  end

  defp api_request(token, method, params) when is_map(params) do
    url = "#{@api_base}/bot#{token}/#{method}"

    opts = [
      json: params,
      connect_options: [timeout: 15_000],
      receive_timeout: 45_000
    ]

    case Req.post(url, opts) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => result}}} ->
        {:ok, result}

      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "description" => desc}}} ->
        {:error, desc}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:error, "unexpected response: #{inspect(body)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
