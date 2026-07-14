export type Frame = {
  kind: "rgb" | "w";
  data: number[];
  keepW?: boolean;
  keepRgb?: boolean;
  keep_w?: boolean;
  keep_rgb?: boolean;
};

export type RGB = [number, number, number];

type PixelState = { r: number; g: number; b: number; w: number };

const EMPTY_PIXEL: PixelState = { r: 0, g: 0, b: 0, w: 0 };

function calculateRedForWFrame(w: number): number {
  const maxW = 255;
  const maxR = 63;
  if (w === 0) {
    return 0;
  }

  const ratio = (maxW - w) / maxW;
  return Math.round(maxR * ratio * ratio);
}

function toDisplayRgb({ r, g, b, w }: PixelState): RGB {
  const wR = calculateRedForWFrame(w);
  const screenR = Math.min(255, Math.round(r + wR - (r * wR) / 255));
  return [screenR, g, b];
}

function frameKeepW(frame: Frame): boolean {
  return frame.keepW ?? frame.keep_w ?? false;
}

function frameKeepRgb(frame: Frame): boolean {
  return frame.keepRgb ?? frame.keep_rgb ?? false;
}

export class FrameBuffer {
  private pixels: PixelState[] = [];

  reset(): void {
    this.pixels = [];
  }

  apply(frame: Frame): void {
    if (frame.kind === "rgb") {
      const keepW = frameKeepW(frame);
      if (!keepW) {
        this.pixels = [];
      }

      const pixelCount = frame.data.length / 3;

      for (let i = 0; i < frame.data.length; i += 3) {
        const index = i / 3;
        const prev = this.pixels[index] ?? EMPTY_PIXEL;

        this.pixels[index] = {
          r: frame.data[i],
          g: frame.data[i + 1],
          b: frame.data[i + 2],
          w: keepW ? prev.w : 0,
        };
      }

      this.pixels.length = pixelCount;
    } else {
      const keepRgb = frameKeepRgb(frame);
      if (!keepRgb) {
        this.pixels = [];
      }

      const pixelCount = frame.data.length;

      for (let i = 0; i < pixelCount; i++) {
        const prev = this.pixels[i] ?? EMPTY_PIXEL;
        const w = frame.data[i];

        this.pixels[i] = keepRgb
          ? { ...prev, w }
          : {
              r: calculateRedForWFrame(w),
              g: 0,
              b: 0,
              w,
            };
      }

      this.pixels.length = pixelCount;
    }
  }

  toRGB(): RGB[] {
    return this.pixels.map(toDisplayRgb);
  }
}

export function applyFrameToPixels(
  buffer: FrameBuffer,
  frame: Frame,
  pixels: RGB[],
  pixelCount: number
): void {
  buffer.apply(frame);
  const merged = buffer.toRGB();

  for (let i = 0; i < pixelCount; i++) {
    pixels[i] = merged[i] ?? [0, 0, 0];
  }
}

export function rgbPixelsFromFrame(frame: Frame): RGB[] {
  const buffer = new FrameBuffer();
  buffer.apply(frame);
  return buffer.toRGB();
}
