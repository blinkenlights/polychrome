import { Hook, makeHook } from "phoenix_typed_hook";
import { Chart, registerables } from 'chart.js';

// Register Chart.js components
Chart.register(...registerables);

interface AlgorithmData {
  raw: Array<{ distance: number; timestamp: number }>;
  sma: Array<{ distance: number; timestamp: number }>;
  ema: Array<{ distance: number; timestamp: number }>;
  median: Array<{ distance: number; timestamp: number }>;
  combined: Array<{ distance: number; timestamp: number }>;
}

interface ProximityData {
  sensor: string;
  algorithms: AlgorithmData;
}

class ProximityChartHook extends Hook {
  chart?: Chart | null;

  constructor() {
    super();
  }

  mounted() {
    const ctx = (this.el as HTMLCanvasElement).getContext('2d');
    if (!ctx) {
      console.error('Could not get canvas context');
      return;
    }

    // Create empty chart
    this.chart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        scales: {
          x: {
            type: 'linear',
            title: {
              display: false,
              text: 'Timestamp'
            },
            ticks: {
              display: false
            }
          },
          y: {
            title: {
              display: true,
              text: 'Distance (mm)'
            },
            beginAtZero: true,
            min: 0,
            max: 3000
          }
        },
        plugins: {
          legend: {
            display: true,
            position: 'top'
          }
        },
        elements: {
          point: {
            radius: 2
          },
          line: {
            borderWidth: 0 // Hide lines globally
          }
        }
      }
    });

    // Listen for messages from LiveView - use arrow function to preserve 'this'
    this.handleEvent("proximity-data", (data: ProximityData) => {
      this.addAlgorithmBatches(data.sensor, data.algorithms);
    });
  }

  addAlgorithmBatches(sensorKey: string, algorithms: AlgorithmData) {
    if (!this.chart) return;

    // Only process combined algorithm for display
    const algorithmsToShow = ['combined'];

    // Process each algorithm, but only show selected ones
    Object.entries(algorithms).forEach(([algorithmName, readings]) => {
      if (algorithmsToShow.includes(algorithmName)) {
        this.addBatch(sensorKey, algorithmName, readings);
      }
    });

    // Update chart once after processing all algorithms
    this.chart.update('none');
  }

  addBatch(sensorKey: string, algorithmName: string, readings: Array<{ distance: number; timestamp: number }>) {
    if (!this.chart) return;

    // Create dataset label combining sensor and algorithm
    const datasetLabel = `${sensorKey} - ${algorithmName.toUpperCase()}`;

    // Find existing dataset or create new one
    let dataset = this.chart.data.datasets.find(d => d.label === datasetLabel);

    if (!dataset) {
      // Create new dataset for this sensor/algorithm combination
      dataset = {
        label: datasetLabel,
        data: [],
        borderWidth: 0, // Hide lines completely
        pointRadius: 2, // Show points with 2px radius
        pointBackgroundColor: this.getAlgorithmColor(algorithmName, sensorKey),
        pointBorderColor: this.getAlgorithmColor(algorithmName, sensorKey),
        pointBorderWidth: 1
      };
      this.chart.data.datasets.push(dataset);
    }

    // Add all readings from the batch
    for (const reading of readings) {
      // Add data point using timestamp as X value
      dataset.data.push({
        x: reading.timestamp,
        y: reading.distance
      });
    }

    const maxPoints = 200;

    // Maintain rolling window - replace the data array if it exceeds max points
    if (dataset.data.length > maxPoints) {
      dataset.data = dataset.data.slice(-maxPoints);
    }
  }

  getAlgorithmColor(algorithmName: string, sensorKey: string, alpha: number = 1): string {
    // Base hue values for each algorithm (0-360)
    const algorithmHues: { [key: string]: number } = {
      raw: 0,        // Red base
      sma: 210,      // Blue base
      ema: 25,       // Orange base
      median: 270,   // Purple base
      combined: 120  // Green base
    };

    // Generate a hash from the sensor key to create variation
    const sensorHash = this.hashString(sensorKey);

    // Get base hue for the algorithm
    const baseHue = algorithmHues[algorithmName] || 200; // Default blue-ish

    // Dramatically increase variation range for better color separation
    // Vary the hue based on sensor key (±120 degrees for maximum separation)
    const hueVariation = (sensorHash % 240) - 120;
    const finalHue = (baseHue + hueVariation + 360) % 360;

    // Vary saturation significantly (50-90% for more vibrant colors)
    const saturation = 50 + (sensorHash % 40);

    // Keep lightness with good variation (35-65% for better contrast)
    const lightness = 35 + (sensorHash % 30);

    // Debug logging to check hash values and colors
    console.log(`Color for ${sensorKey} (${algorithmName}): hash=${sensorHash}, hue=${finalHue}, sat=${saturation}, light=${lightness}`);

    return `hsla(${finalHue}, ${saturation}%, ${lightness}%, ${alpha})`;
  }

  // Improved hash function for better distribution with similar strings
  private hashString(str: string): number {
    let hash = 5381; // djb2 hash initial value
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash * 33) ^ char) >>> 0; // Use XOR and ensure unsigned 32-bit
    }

    // Additional mixing to improve distribution for similar strings
    hash = ((hash >>> 16) ^ hash) * 0x45d9f3b;
    hash = ((hash >>> 16) ^ hash) * 0x45d9f3b;
    hash = (hash >>> 16) ^ hash;

    return Math.abs(hash);
  }

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
}

export default makeHook(ProximityChartHook);