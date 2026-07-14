defmodule Octopus.Radar.TrackMerge do
  @moduledoc """
  Merges nearby radar tracks into one person (multi-sensor duplicates).

  Uses union-find clustering in XY, then averages position and velocity per
  cluster. Shared by `PanelActivity` and crowd apps.
  """

  @default_radius_m 0.75
  @max_radius_delta_m 0.35

  @type person :: %{
          required(:id) => pos_integer(),
          required(:x) => float(),
          required(:y) => float(),
          optional(:vx) => float(),
          optional(:vy) => float()
        }

  @doc """
  Returns a de-duplicated person list.

  Only merges **cross-sensor duplicates**: pairs from different radar devices
  within `radius_m` and with similar radius (same person, not two people on the
  same bearing at different distances). Tracks from the same device are never
  merged.
  """
  @spec merge([person()], float()) :: [person()]
  def merge(people, radius_m \\ @default_radius_m)

  def merge([], _radius_m), do: []

  def merge(people, radius_m) when is_list(people) do
    people
    |> cluster(radius_m)
    |> Enum.flat_map(&resolve_cluster/1)
  end

  @doc false
  @spec device_id(person()) :: non_neg_integer()
  def device_id(%{id: id}) when id >= 10_000, do: div(id, 10_000)
  def device_id(%{id: _id}), do: 0

  defp resolve_cluster(cluster) do
    if duplicate_devices?(cluster), do: cluster, else: [merge_cluster(cluster)]
  end

  defp duplicate_devices?(cluster) do
    cluster
    |> Enum.map(&device_id/1)
    |> Enum.frequencies()
    |> Enum.any?(fn {_device, count} -> count > 1 end)
  end

  defp merge_cluster([person]), do: person

  defp merge_cluster(cluster) do
    n = length(cluster)

    %{
      id: cluster |> Enum.map(& &1.id) |> Enum.min(),
      x: sum(cluster, :x) / n,
      y: sum(cluster, :y) / n,
      vx: sum_optional(cluster, :vx) / n,
      vy: sum_optional(cluster, :vy) / n
    }
  end

  defp sum(items, key), do: Enum.sum(Enum.map(items, &Map.fetch!(&1, key)))

  defp sum_optional(items, key), do: Enum.sum(Enum.map(items, &Map.get(&1, key, 0.0)))

  defp cluster(people, threshold) do
    n = length(people)

    parent =
      Enum.reduce(0..(n - 1)//1, %{}, fn i, acc ->
        Map.put(acc, i, i)
      end)

    indexed = Enum.with_index(people)

    parent =
      Enum.reduce(indexed, parent, fn {p1, i}, acc ->
        Enum.reduce(indexed, acc, fn {p2, j}, acc2 ->
          if i < j and should_merge?(p1, p2, threshold) do
            union_parent(acc2, i, j)
          else
            acc2
          end
        end)
      end)

    indexed
    |> Enum.group_by(fn {_, i} -> elem(find_parent(parent, i), 0) end, fn {p, _} -> p end)
    |> Map.values()
  end

  defp find_parent(parent, i) do
    case Map.fetch!(parent, i) do
      ^i ->
        {i, parent}

      p ->
        {root, parent} = find_parent(parent, p)
        {root, Map.put(parent, i, root)}
    end
  end

  defp union_parent(parent, i, j) do
    {root_i, parent} = find_parent(parent, i)
    {root_j, parent} = find_parent(parent, j)
    Map.put(parent, root_j, root_i)
  end

  defp should_merge?(p1, p2, threshold) do
    dist_xy(p1, p2) <= threshold and
      device_id(p1) != device_id(p2) and
      abs(radius(p1) - radius(p2)) <= @max_radius_delta_m
  end

  defp radius(%{x: x, y: y}), do: :math.sqrt(x * x + y * y)

  defp dist_xy(%{x: x1, y: y1}, %{x: x2, y: y2}) do
    dx = x1 - x2
    dy = y1 - y2
    :math.sqrt(dx * dx + dy * dy)
  end
end
