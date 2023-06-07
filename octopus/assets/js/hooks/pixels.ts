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
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
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

export function setup(canvas: HTMLCanvasElement) {
  const id = canvas.id;
  let pixelOffset = 0;

  let layout: Layout;
  let pixels: RGB[] = [];

  const ctx = canvas.getContext("2d");
  if (!ctx) {
    return;
  }

  resize(canvas);

  window.addEventListener("resize", () => resize(canvas));

  [`layout:${id}`, "layout:*"].forEach((event) => {
    this.handleEvent(event, ({ layout: newLayout }: { layout: Layout }) => {
      layout = newLayout;
    });
  });

  [`frame:${id}`, "frame:*"].forEach((event) => {
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
          pixels = frame.data.reduce((acc: RGB[], value, index) => {
            const pixelIndex = Math.floor(index / 3);
            if (!acc[pixelIndex]) {
              acc[pixelIndex] = [0, 0, 0];
            }
            acc[pixelIndex][index % 3] = value;
            return acc;
          }, []);
          break;
        }
        case "rgbw":
        case "audio":
          break;
      }
    });
  });

  [`config:${id}`, "config:*"].forEach((event) => {
    this.handleEvent(event, ({ config: _ }: { config: Config }) => {});
  });

  ["pixel_offset", "pixel_offset:*"].forEach((event) => {
    this.handleEvent(event, ({ offset: newOffset }: { offset: number }) => {
      pixelOffset = newOffset;
    });
  });

  const draw = () => {
    if (!layout) {
      window.requestAnimationFrame(draw);
      return;
    }

    resize(canvas);

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
