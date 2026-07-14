import { Hook, makeHook } from "phoenix_typed_hook";

import { Frame, FrameBuffer, RGB } from "./shared/frame";

interface Layout {
  imageSize: [number, number];
  pixelSize: [number, number];
  pixelMargin: [number, number, number, number];
  positions: [number, number][];
  backgroundImage: string;
  width: number;
  height: number;
}

interface Config {}

function resizeCanvas(canvas: HTMLCanvasElement): boolean {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const width = Math.max(1, Math.round(rect.width * dpr));
  const height = Math.max(1, Math.round(rect.height * dpr));

  if (canvas.width === width && canvas.height === height) {
    return false;
  }

  canvas.width = width;
  canvas.height = height;
  return true;
}

function applyLayoutBackground(canvas: HTMLCanvasElement, layout: Layout) {
  if (layout.backgroundImage) {
    canvas.style.backgroundImage = `url(${layout.backgroundImage})`;
  } else {
    canvas.style.backgroundImage = "";
  }
}

function desaturate([r, g, b]: RGB, amount: number): RGB {
  amount = 1.0 - amount;
  const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return [l + (r - l) * amount, l + (g - l) * amount, l + (b - l) * amount];
}

function brighten([r, g, b]: RGB, amount: number): RGB {
  return [
    r + (255 - r) * amount,
    g + (255 - g) * amount,
    b + (255 - b) * amount,
  ];
}

const DESATURATION_AMOUNT = 0.15;
const BRIGHTEN_AMOUNT = 0.1;

function drawPanelGrid(ctx: CanvasRenderingContext2D, layout: Layout) {
  ctx.strokeStyle = "rgba(128, 128, 128, 0.5)";
  ctx.lineWidth = 0.5;

  const totalWidth = layout.imageSize[0];
  const totalHeight = layout.imageSize[1];
  const pixelWidth = layout.pixelSize[0];
  const pixelHeight = layout.pixelSize[1];

  for (let x = 0; x <= totalWidth; x += pixelWidth) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, totalHeight);
    ctx.stroke();
  }

  for (let y = 0; y <= totalHeight; y += pixelHeight) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(totalWidth, y);
    ctx.stroke();
  }

  ctx.strokeStyle = "rgba(200, 200, 200, 1.0)";
  ctx.lineWidth = 1;
  ctx.strokeRect(0, 0, totalWidth, totalHeight);
}

class PixelsHook extends Hook {
  _cleanup?: () => void;

  mounted() {
    const canvas = this.el as HTMLCanvasElement;
    const id = canvas.id;
    let pixelOffset = 0;
    let layout: Layout | undefined;
    let pixels: RGB[] = [];
    const buffer = new FrameBuffer();
    let drawQueued = false;

    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }

    const draw = () => {
      drawQueued = false;
      if (!layout) {
        return;
      }

      resizeCanvas(canvas);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.save();

      const isGenericLayout =
        !layout.backgroundImage || layout.backgroundImage === "";

      const scale = isGenericLayout
        ? Math.min(
            1.0,
            Math.min(
              canvas.width / layout.imageSize[0],
              canvas.height / layout.imageSize[1]
            )
          )
        : Math.min(
            canvas.width / layout.imageSize[0],
            canvas.height / layout.imageSize[1]
          );

      const offsetX = canvas.width / 2 - (layout.imageSize[0] / 2) * scale;
      const offsetY = canvas.height / 2 - (layout.imageSize[1] / 2) * scale;

      ctx.translate(offsetX, offsetY);
      ctx.scale(scale, scale);

      for (let i = 0; i < layout.positions.length; i++) {
        const [x, y] = layout.positions[i];
        const pixel = pixels[i + pixelOffset] || [0, 0, 0];
        const [r, g, b] = brighten(
          desaturate(pixel, DESATURATION_AMOUNT),
          BRIGHTEN_AMOUNT
        );

        ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
        ctx.fillRect(
          x + layout.pixelMargin[0],
          y + layout.pixelMargin[1],
          layout.pixelSize[0] - layout.pixelMargin[0] - layout.pixelMargin[2],
          layout.pixelSize[1] - layout.pixelMargin[1] - layout.pixelMargin[3]
        );
      }

      if (isGenericLayout) {
        drawPanelGrid(ctx, layout);
      }

      ctx.restore();
    };

    const scheduleDraw = () => {
      if (drawQueued) {
        return;
      }
      drawQueued = true;
      window.requestAnimationFrame(draw);
    };

    resizeCanvas(canvas);

    this.handleEvent(`layout:${id}`, ({ layout: newLayout }: { layout: Layout }) => {
      layout = newLayout;
      buffer.reset();
      applyLayoutBackground(canvas, newLayout);
      scheduleDraw();
    });

    this.handleEvent(`frame:${id}`, ({ frame: frame }: { frame: Frame }) => {
      buffer.apply(frame);
      pixels = buffer.toRGB();
      scheduleDraw();
    });

    this.handleEvent(`config:${id}`, ({ config: _ }: { config: Config }) => {});

    this.handleEvent(`pixel_offset:${id}`, ({ offset: newOffset }: { offset: number }) => {
      pixelOffset = newOffset;
      scheduleDraw();
    });

    let resizeTimer: number | undefined;
    const onResize = () => {
      if (resizeTimer != null) {
        window.clearTimeout(resizeTimer);
      }
      resizeTimer = window.setTimeout(() => {
        resizeTimer = undefined;
        if (resizeCanvas(canvas)) {
          scheduleDraw();
        }
      }, 150);
    };
    const resizeObserver = new ResizeObserver(onResize);
    resizeObserver.observe(canvas);
    window.addEventListener("resize", onResize);

    this._cleanup = () => {
      if (resizeTimer != null) {
        window.clearTimeout(resizeTimer);
      }
      resizeObserver.disconnect();
      window.removeEventListener("resize", onResize);
    };
  }

  destroyed() {
    this._cleanup?.();
  }
}

export default makeHook(PixelsHook);
