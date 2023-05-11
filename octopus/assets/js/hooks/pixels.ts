function resize(canvas: HTMLCanvasElement) {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
}

type RGB = [number, number, number];

interface Layout {
  imageSize: [number, number];
  pixelSize: [number, number];
  positions: [number, number][];
}

interface Config {}

interface Frame {
  data: Uint8Array;
  palette: RGB[];
}

export function setup(
  id: string,
  canvas: HTMLCanvasElement,
  pixelImageUrl: string
) {
  let pixels = new Uint8Array();
  let colorPalette: RGB[] = [];
  let layout: Layout;
  let lastCanvasBoundingClientRect = canvas.getBoundingClientRect();

  const pixelImage = new Image();
  pixelImage.src = pixelImageUrl;

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
      pixels = frame.data;
      colorPalette = frame.palette;
    });
  });

  [`config:${id}`, "config:*"].forEach((event) => {
    this.handleEvent(event, ({ config: _ }: { config: Config }) => {});
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

    layout.positions.forEach(([x, y], i) => {
      const pixel = pixels[i];

      if (pixel !== undefined) {
        let [r, g, b] = colorPalette[pixel];
        ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
      } else {
        ctx.fillStyle = "hsl(40, 80%, 5%)";
      }

      ctx.fillRect(x, y, layout.pixelSize[0], layout.pixelSize[1]);

      ctx.drawImage(pixelImage, x, y, layout.pixelSize[0], layout.pixelSize[1]);
    });

    ctx.restore();

    window.requestAnimationFrame(draw);
  };

  window.requestAnimationFrame(draw);
}
