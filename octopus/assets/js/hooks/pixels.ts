import { Hook, makeHook } from "phoenix_typed_hook";

type RGB = [number, number, number];

interface Layout {
  imageSize: [number, number];
  pixelSize: [number, number];
  pixelMargin: [number, number, number, number];
  positions: [number, number][];
}

interface Config {}

type Frame =
  | { kind: "indexed"; data: number[]; palette: RGB[] }
  | { kind: "rgb"; data: number[] }
  | { kind: "rgbw"; data: number[] }
  | { kind: "audio"; uri: string; channel: number };

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
      });
    });

    [`frame:${id}`, "frame:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ frame: frame }: { frame: Frame }) => {
        switch (frame.kind) {
          case "indexed": {
            pixels = frame.data.map((pixel) => {
              if (pixel < frame.palette.length) {
                return frame.palette[pixel];
              }
              return frame.palette[0] || [0, 0, 0];
            });
            break;
          }
          case "rgb": {
            const numPixels = frame.data.length / 3;
            pixels = new Array(numPixels).fill([0, 0, 0]);
            for (let i = 0; i < numPixels; i++) {
              const pixelOffset = i * 3;
              const r = frame.data[pixelOffset];
              const g = frame.data[pixelOffset + 1];
              const b = frame.data[pixelOffset + 2];

              pixels[i] = [r, g, b];
            }
            break;
          }
          case "rgbw":
          case "audio":
            break;
        }
      });
    });

    [`config:${id}`, "config:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ config: _ }: { config: Config }) => {});
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

      const scale = Math.min(
        canvas.width / layout.imageSize[0],
        canvas.height / layout.imageSize[1]
      );

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
        ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
        ctx.shadowColor = ctx.fillStyle;
        ctx.shadowBlur = layout.pixelSize[0] / 3;

        ctx.fillRect(
          x + layout.pixelMargin[0],
          y + layout.pixelMargin[1],
          layout.pixelSize[0] - layout.pixelMargin[0] - layout.pixelMargin[2],
          layout.pixelSize[1] - layout.pixelMargin[1] - layout.pixelMargin[3]
        );
      });

      ctx.restore();

      window.requestAnimationFrame(draw);
    };

    window.requestAnimationFrame(draw);
  }
}

export default makeHook(PixelsHook);
