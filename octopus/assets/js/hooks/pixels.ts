import { Hook, makeHook } from "phoenix_typed_hook";

import { Frame, RGB, rgbPixelsFromFrame } from "./shared/frame";

interface Layout {
  imageSize: [number, number];
  pixelSize: [number, number];
  pixelMargin: [number, number, number, number];
  positions: [number, number][];
  backgroundImage: string;
  width: number;
  height: number;
}

interface Config { }

function resize(canvas: HTMLCanvasElement) {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  if (
    canvas.width !== rect.width * dpr ||
    canvas.height !== rect.height * dpr
  ) {
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
  }
}

// Debounces a function based on the current time.
// This is useful for animations, where we want to debounce a function
// that is called on every frame, but we want to debounce it based on
// the current time, not the time the function was last called.
function debounceAnimatedFunction<T extends (...args: any[]) => any>(
  func: T,
  delay: number = 100
): T {
  let lastExecution = performance.now() - delay;
  return function (this: any, ...args: any[]) {
    const now = performance.now();
    if (now - lastExecution >= delay) {
      lastExecution = now;
      func.apply(this, args);
    }
  } as any;
}

function desaturate([r, g, b]: RGB, amount: number): RGB {
  amount = 1.0 - amount;
  const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return [l + (r - l) * amount, l + (g - l) * amount, l + (b - l) * amount];
}

function brighten([r, g, b]: RGB, amount: number): RGB {
  const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return [
    r + (255 - r) * amount,
    g + (255 - g) * amount,
    b + (255 - b) * amount,
  ];
}

const DESATURATION_AMOUNT = 0.15;
const BRIGHTEN_AMOUNT = 0.1;

function drawPanelGrid(ctx: CanvasRenderingContext2D, layout: Layout) {
  console.log("Drawing grid for layout:", layout.width, "x", layout.height, "pixel size:", layout.pixelSize);

  // Draw more visible gray lines to show panel boundaries and pixel grid
  ctx.strokeStyle = "rgba(128, 128, 128, 0.5)"; // Semi-transparent gray
  ctx.lineWidth = 0.5;

  // For generic layouts, we want to draw a grid that shows individual pixels
  // Use the actual image size as the total canvas area
  const totalWidth = layout.imageSize[0];
  const totalHeight = layout.imageSize[1];

  console.log("Grid dimensions:", totalWidth, "x", totalHeight);

  // Draw pixel grid lines
  const pixelWidth = layout.pixelSize[0];
  const pixelHeight = layout.pixelSize[1];

  // Draw vertical lines (one line between each pixel column)
  for (let x = 0; x <= totalWidth; x += pixelWidth) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, totalHeight);
    ctx.stroke();
  }

  // Draw horizontal lines (one line between each pixel row)
  for (let y = 0; y <= totalHeight; y += pixelHeight) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(totalWidth, y);
    ctx.stroke();
  }

  // Draw a border around the entire grid
  ctx.strokeStyle = "rgba(200, 200, 200, 1.0)"; // Light gray border
  ctx.lineWidth = 1;
  ctx.strokeRect(0, 0, totalWidth, totalHeight);
}

class PixelsHook extends Hook {
  mounted() {
    const canvas = this.el as HTMLCanvasElement;

    const id = canvas.id;
    let pixelOffset = 0;

    let layout: Layout;
    let pixels: RGB[] = [];

    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }

    resize(canvas);

    [`layout:${id}`, "layout:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ layout: newLayout }: { layout: Layout }) => {
        layout = newLayout;
        console.log("Layout received:", layout);
        console.log("Is generic layout:", !layout.backgroundImage || layout.backgroundImage === "");
      });
    });

    [`frame:${id}`, "frame:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ frame: frame }: { frame: Frame }) => {
        pixels = rgbPixelsFromFrame(frame);
        console.log("Frame received, pixels count:", pixels.length);
      });
    });

    [`config:${id}`, "config:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ config: _ }: { config: Config }) => { });
    });

    [`pixel_offset:${id}`, "pixel_offset:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ offset: newOffset }: { offset: number }) => {
        pixelOffset = newOffset;
      });
    });

    const debouncedResize = debounceAnimatedFunction(resize, 50);

    const draw = () => {
      if (!layout) {
        window.requestAnimationFrame(draw);
        return;
      }

      debouncedResize(canvas);

      ctx.clearRect(0, 0, canvas.width, canvas.height);

      ctx.save();

      // Check if this is a generic layout (empty background image)
      const isGenericLayout = !layout.backgroundImage || layout.backgroundImage === "";

      let scale: number;
      if (isGenericLayout) {
        // For generic layouts, don't scale beyond 1.0 to preserve pixel size
        scale = Math.min(
          1.0,
          Math.min(
            canvas.width / layout.imageSize[0],
            canvas.height / layout.imageSize[1]
          )
        );
      } else {
        // For image-based layouts, scale to fit the window as before
        scale = Math.min(
          canvas.width / layout.imageSize[0],
          canvas.height / layout.imageSize[1]
        );
      }

      const offsetX = canvas.width / 2 - (layout.imageSize[0] / 2) * scale;
      const offsetY = canvas.height / 2 - (layout.imageSize[1] / 2) * scale;

      ctx.translate(offsetX, offsetY);
      ctx.scale(scale, scale);

      const positionsWithPixels: [
        [number, number],
        [number, number, number] | undefined
      ][] = layout.positions.map((pos, i) => [pos, pixels[i + pixelOffset]]);

      positionsWithPixels.forEach(([[x, y], pixel]) => {
        let rgb = pixel || [0, 0, 0];

        let [r, g, b] = brighten(
          desaturate(rgb, DESATURATION_AMOUNT),
          BRIGHTEN_AMOUNT
        );
        const fillStyle = `rgb(${r}, ${g}, ${b})`;
        ctx.fillStyle = fillStyle;
        ctx.shadowColor = fillStyle;
        ctx.shadowBlur = layout.pixelSize[0] / 3;

        ctx.fillRect(
          x + layout.pixelMargin[0],
          y + layout.pixelMargin[1],
          layout.pixelSize[0] - layout.pixelMargin[0] - layout.pixelMargin[2],
          layout.pixelSize[1] - layout.pixelMargin[1] - layout.pixelMargin[3]
        );
      });

      if (isGenericLayout) {
        // Draw panel grid lines AFTER pixels for generic layouts
        drawPanelGrid(ctx, layout);
      }

      ctx.restore();

      window.requestAnimationFrame(draw);
    };

    window.requestAnimationFrame(draw);
  }
}

export default makeHook(PixelsHook);
