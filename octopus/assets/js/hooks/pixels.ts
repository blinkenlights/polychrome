type RGB = [number, number, number];

interface Layout {
  imageSize: [number, number];
  pixelSize: [number, number];
  pixelMargin: [number, number, number, number];
  positions: [number, number][];
  pixelImage: string;
}

interface Config {}

interface Frame {
  data: Uint8Array;
  palette: RGB[];
}

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

const DESATURATION_AMOUNT = 0.1;
const BRIGHTEN_AMOUNT = 0.05;

export function setup(canvas: HTMLCanvasElement) {
  const id = canvas.id;
  const pixelImage = new Image();
  let pixelOffset = 0;

  let layout: Layout;
  let pixels = new Uint8Array();
  let colorPalette: RGB[] = [];
  let lastCanvasBoundingClientRect = canvas.getBoundingClientRect();

  const ctx = canvas.getContext("2d");
  if (!ctx) {
    return;
  }

  resize(canvas);

  window.addEventListener("resize", () => resize(canvas));

  [`layout:${id}`, "layout:*"].forEach((event) => {
    this.handleEvent(event, ({ layout: newLayout }: { layout: Layout }) => {
      layout = newLayout;
      pixelImage.src = layout.pixelImage;
    });
  });

  [`frame:${id}`, "frame:*"].forEach((event) => {
    this.handleEvent(event, ({ frame: frame }: { frame: Frame }) => {
      pixels = frame.data;
      colorPalette = frame.palette;
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

    const rect = canvas.getBoundingClientRect();
    if (rect !== lastCanvasBoundingClientRect) {
      resize(canvas);
      lastCanvasBoundingClientRect = rect;
    }

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

    const positionsWithPixels: [[number, number], number | undefined][] =
      layout.positions.map((pos, i) => [pos, pixels[i + pixelOffset]]);

    positionsWithPixels.forEach(([[x, y], pixel], i) => {
      let rgb: RGB = [0, 0, 0];

      if (pixel !== undefined && colorPalette[pixel] !== undefined) {
        rgb = colorPalette[pixel];
      }

      let [r, g, b] = brighten(
        desaturate(rgb, DESATURATION_AMOUNT),
        BRIGHTEN_AMOUNT
      );
      ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;

      ctx.fillRect(
        x + layout.pixelMargin[0],
        y + layout.pixelMargin[1],
        layout.pixelSize[0] - layout.pixelMargin[0] - layout.pixelMargin[2],
        layout.pixelSize[1] - layout.pixelMargin[1] - layout.pixelMargin[3]
      );
    });

    ctx.globalCompositeOperation = "screen";
    ctx.globalAlpha = 0.5;

    positionsWithPixels.forEach(([[x, y], _pixel]) => {
      ctx.drawImage(pixelImage, x, y, layout.pixelSize[0], layout.pixelSize[1]);
    });

    ctx.restore();

    window.requestAnimationFrame(draw);
  };

  window.requestAnimationFrame(draw);
}
