defmodule OctopusWeb.ProximityLive do
  use OctopusWeb, :live_view

  alias Octopus.Events.Event.Proximity, as: ProximityEvent

  @batch_size 2

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Octopus.Events.Router.subscribe()
    end

    socket =
      assign(socket,
        buffers: %{}
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:events_router, {:proximity_event, %ProximityEvent{} = event}}, socket) do
    sensor_key = "sensor_#{event.panel}_#{event.sensor}"
    socket = add_to_buffers(socket, sensor_key, event)
    {:noreply, socket}
  end

  # Ignore other events from the router
  def handle_info({:events_router, _other_event}, socket) do
    {:noreply, socket}
  end

  defp add_to_buffers(socket, sensor_key, %ProximityEvent{} = event) do
    current_buffers =
      Map.get(socket.assigns.buffers, sensor_key, %{
        raw: [],
        sma: [],
        ema: [],
        median: [],
        combined: []
      })

    # Add to each buffer
    updated_buffers = %{
      raw: [%{distance: event.distance, timestamp: event.timestamp} | current_buffers.raw],
      sma: [%{distance: event.distance_sma, timestamp: event.timestamp} | current_buffers.sma],
      ema: [%{distance: event.distance_ema, timestamp: event.timestamp} | current_buffers.ema],
      median: [
        %{distance: event.distance_median, timestamp: event.timestamp} | current_buffers.median
      ],
      combined: [
        %{distance: event.distance_combined, timestamp: event.timestamp}
        | current_buffers.combined
      ]
    }

    # Check if any buffer is ready to send
    ready_to_send =
      Enum.any?(updated_buffers, fn {_key, buffer} ->
        length(buffer) >= @batch_size
      end)

    if ready_to_send do
      chart_data = %{
        sensor: sensor_key,
        algorithms: %{
          raw: Enum.reverse(Enum.take(updated_buffers.raw, @batch_size)),
          sma: Enum.reverse(Enum.take(updated_buffers.sma, @batch_size)),
          ema: Enum.reverse(Enum.take(updated_buffers.ema, @batch_size)),
          median: Enum.reverse(Enum.take(updated_buffers.median, @batch_size)),
          combined: Enum.reverse(Enum.take(updated_buffers.combined, @batch_size))
        }
      }

      socket
      |> push_event("proximity-data", chart_data)
      |> assign(buffers: Map.delete(socket.assigns.buffers, sensor_key))
    else
      assign(socket, buffers: Map.put(socket.assigns.buffers, sensor_key, updated_buffers))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full p-4">
      <div class="bg-white shadow rounded-lg p-4">
        <h1 class="text-2xl font-bold mb-4">Proximity Readings - Algorithm Comparison</h1>
        <div class="mb-4">
          <div class="flex flex-wrap gap-4 text-sm">
            <div class="flex items-center">
              <div class="w-4 h-0.5 bg-red-500 mr-2"></div>
              <span>Raw</span>
            </div>
            <div class="flex items-center">
              <div class="w-4 h-0.5 bg-orange-500 mr-2"></div>
              <span>Combined (Median + EMA)</span>
            </div>
          </div>
        </div>
        <div class="w-full h-96">
          <canvas id="proximity-chart" phx-hook="ProximityChart" class="w-full h-full"></canvas>
        </div>
        <div class="mt-4 text-sm text-gray-600">
          <p>This chart compares raw proximity sensor data with a combined smoothing algorithm.</p>
          <p>The comparison shows the difference between unfiltered and processed sensor readings:</p>
          <ul class="list-disc list-inside mt-2 space-y-1">
            <li><strong>Raw:</strong> Shows all sensor noise and spikes from the proximity sensor</li>
            <li>
              <strong>Combined:</strong>
              Uses median filter first, then exponential moving average for optimal smoothing
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
