defmodule Octopus.Radar.SensorTransition do
  @moduledoc """
  Ecto schema for persisted radar sensor status transitions.

  Each row records a single status change: the new `status` the sensor entered
  and the wall-clock time (`occurred_at_ms`, Unix milliseconds) at which the
  transition was observed.  Only genuine changes are written — duplicate
  broadcasts of the same status produce no row.

  On `Octopus.Radar.Stats` startup all rows are loaded per device, sorted
  chronologically, and replayed through the same transition logic that drives
  the in-memory stats, so dropout / retry counts and per-status durations
  survive restarts.
  """

  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  alias Octopus.Repo

  schema "radar_sensor_transitions" do
    field :device_id, :integer
    field :status, :string
    field :occurred_at_ms, :integer

    timestamps(updated_at: false)
  end

  @doc """
  Asynchronously insert a new transition row.

  The insert runs in a fire-and-forget `Task` so that the calling GenServer
  is never blocked by a slow write.
  """
  @spec record(pos_integer(), atom(), integer()) :: :ok
  def record(device_id, status, occurred_at_ms)
      when is_integer(device_id) and is_atom(status) and is_integer(occurred_at_ms) do
    Task.start(fn ->
      %__MODULE__{
        device_id: device_id,
        status: Atom.to_string(status),
        occurred_at_ms: occurred_at_ms
      }
      |> Repo.insert!()
    end)

    :ok
  end

  @doc """
  Return all transitions for `device_id`, ordered oldest-first, as
  `[{status_atom, occurred_at_ms}]`.
  """
  @spec list_for_device(pos_integer()) :: [{atom(), integer()}]
  def list_for_device(device_id) do
    from(t in __MODULE__,
      where: t.device_id == ^device_id,
      order_by: [asc: t.occurred_at_ms],
      select: {t.status, t.occurred_at_ms}
    )
    |> Repo.all()
    |> Enum.map(fn {status_str, ms} -> {String.to_existing_atom(status_str), ms} end)
  end

  @doc """
  Return all transitions grouped by device_id: `%{device_id => [{status_atom, ms}]}`,
  each list sorted oldest-first.  Used for bulk loading at Stats startup.
  """
  @spec list_all_grouped() :: %{pos_integer() => [{atom(), integer()}]}
  def list_all_grouped do
    from(t in __MODULE__,
      order_by: [asc: t.device_id, asc: t.occurred_at_ms],
      select: {t.device_id, t.status, t.occurred_at_ms}
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {device_id, _, _} -> device_id end,
      fn {_, status_str, ms} -> {String.to_existing_atom(status_str), ms} end
    )
  end
end
