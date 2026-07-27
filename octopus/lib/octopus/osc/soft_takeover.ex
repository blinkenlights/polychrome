defmodule Octopus.Osc.SoftTakeover do
  @moduledoc """
  Soft takeover (pickup) state for continuous OSC controls.

  Per `{client, param}`: unmatched until the incoming value reaches the
  current actual (within epsilon), then matched and values apply freely.
  After UI-Sync pushes actuals to a client, that client is marked matched
  so faders are immediately playable.
  """

  use Agent

  @type client :: {tuple(), non_neg_integer()} | :local
  @type key :: atom()

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc false
  def reset! do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  def matched?(client, key) do
    Agent.get(__MODULE__, &Map.get(&1, {client, key}, false))
  end

  def mark_matched(client, key) do
    Agent.update(__MODULE__, &Map.put(&1, {client, key}, true))
  end

  def mark_matched_many(_client, []), do: :ok

  def mark_matched_many(client, keys) when is_list(keys) do
    Agent.update(__MODULE__, fn state ->
      Enum.reduce(keys, state, fn key, acc -> Map.put(acc, {client, key}, true) end)
    end)
  end

  def mark_clients_matched(clients, keys) when is_list(clients) and is_list(keys) do
    Enum.each(clients, &mark_matched_many(&1, keys))
  end

  def mark_unmatched(client, key) do
    Agent.update(__MODULE__, &Map.put(&1, {client, key}, false))
  end

  @doc """
  Returns true when the incoming continuous value may be applied.
  Marks the binding matched when accepted via pickup or already matched.
  """
  def accept?(client, key, incoming, actual, opts \\ [])

  def accept?(client, key, incoming, actual, opts)
      when is_number(incoming) and is_number(actual) do
    epsilon = Keyword.get(opts, :epsilon, epsilon_for(key))

    cond do
      matched?(client, key) ->
        true

      abs(incoming - actual) <= epsilon ->
        mark_matched(client, key)
        true

      true ->
        false
    end
  end

  # Non-numeric / missing actual: do not block (toggles, missing state).
  def accept?(client, key, _incoming, _actual, _opts) do
    mark_matched(client, key)
    true
  end

  defp epsilon_for(:speed), do: 0.05
  defp epsilon_for(:global_speed), do: 0.05
  defp epsilon_for(:brightness_percent), do: 1.0
  defp epsilon_for(:saturation_percent), do: 1.0
  defp epsilon_for(:bleeding), do: 1.0
  defp epsilon_for(:roll_rate), do: 1.0
  defp epsilon_for(:orbit_rate), do: 0.5
  defp epsilon_for(:elev_base), do: 0.1
  defp epsilon_for(:tilt_scale), do: 0.1
  defp epsilon_for(:zoom_base), do: 0.05
  defp epsilon_for(:color_interval), do: 0.5
  defp epsilon_for(_), do: 0.05
end
