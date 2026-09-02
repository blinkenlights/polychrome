import { Hook, makeHook } from "phoenix_typed_hook";

import { Frame, FrameBuffer, RGB } from "./shared/frame";

interface PanelInfo {
  panel: number;
  controller: string;
  wiring: string;
  width: number;
  height: number;
}

interface Layout {
  imageSize: [number, number];
  pixelSize: [number, number];
  pixelMargin: [number, number, number, number];
  positions: [number, number][];
  backgroundImage: string;
  width: number;
  height: number;
  // Set only for circular installations' ring view (see
  // `Octopus.Installation.CircularLayout`). When present, `positions` holds
  // per-pixel offsets relative to that pixel's panel center (pre-rotation)
  // instead of absolute image coordinates.
  panelCenters?: [number, number][] | null;
  panelRotations?: number[] | null;
  // A layout that is meant to fill its box (the studio strip) rather than be
  // capped at 1:1 like the development view.
  fill?: boolean | null;
  // Set on every layout, for the hover tooltip.
  panelPixelCount?: number | null;
  panelInfo?: PanelInfo[] | null;
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

function isRingLayout(layout: Layout): boolean {
  return Boolean(
    layout.panelCenters &&
      layout.panelCenters.length > 0 &&
      layout.panelRotations &&
      layout.panelPixelCount
  );
}

// Draws one panel's pixels as a rigid, rotated block: translate to the
// panel's center, rotate by its ring bearing, then draw each pixel at its
// (unrotated) offset from that center. The pixel matrix itself is never
// sheared — only the panel as a whole is rotated.
function drawRingPixels(
  ctx: CanvasRenderingContext2D,
  layout: Layout,
  pixels: RGB[],
  pixelOffset: number
) {
  const panelPixelCount = layout.panelPixelCount as number;
  const centers = layout.panelCenters as [number, number][];
  const rotations = layout.panelRotations as number[];
  const [marginLeft, marginTop, marginRight, marginBottom] = layout.pixelMargin;
  const pixelW = layout.pixelSize[0] - marginLeft - marginRight;
  const pixelH = layout.pixelSize[1] - marginTop - marginBottom;

  for (let panelIndex = 0; panelIndex < centers.length; panelIndex++) {
    const [cx, cy] = centers[panelIndex];
    const angleRad = (rotations[panelIndex] * Math.PI) / 180;

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(angleRad);

    const base = panelIndex * panelPixelCount;
    for (let j = 0; j < panelPixelCount; j++) {
      const [lx, ly] = layout.positions[base + j];
      const pixel = pixels[base + j + pixelOffset] || [0, 0, 0];
      const [r, g, b] = brighten(
        desaturate(pixel, DESATURATION_AMOUNT),
        BRIGHTEN_AMOUNT
      );

      ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
      ctx.fillRect(
        lx - layout.pixelSize[0] / 2 + marginLeft,
        ly - layout.pixelSize[1] / 2 + marginTop,
        pixelW,
        pixelH
      );
    }

    ctx.restore();
  }
}

// Axis-aligned (linear/image layouts) or oriented (ring layout) panel
// bounding box, in image space, used to hit-test the mouse for the hover
// tooltip.
type PanelHitArea =
  | { kind: "aabb"; minX: number; maxX: number; minY: number; maxY: number }
  | {
      kind: "obb";
      cx: number;
      cy: number;
      cosT: number;
      sinT: number;
      halfW: number;
      halfH: number;
    };

function computePanelHitAreas(layout: Layout): PanelHitArea[] {
  const count = layout.panelPixelCount;
  if (!count || layout.positions.length === 0) {
    return [];
  }

  const numPanels = Math.floor(layout.positions.length / count);
  const halfPxW = layout.pixelSize[0] / 2;
  const halfPxH = layout.pixelSize[1] / 2;
  const ring = isRingLayout(layout);
  const areas: PanelHitArea[] = [];

  for (let p = 0; p < numPanels; p++) {
    const base = p * count;
    let minX = Infinity;
    let maxX = -Infinity;
    let minY = Infinity;
    let maxY = -Infinity;

    for (let j = 0; j < count; j++) {
      const [x, y] = layout.positions[base + j];
      minX = Math.min(minX, x);
      maxX = Math.max(maxX, x);
      minY = Math.min(minY, y);
      maxY = Math.max(maxY, y);
    }

    if (ring && layout.panelCenters && layout.panelRotations) {
      const [cx, cy] = layout.panelCenters[p];
      const angleRad = (layout.panelRotations[p] * Math.PI) / 180;

      areas.push({
        kind: "obb",
        cx,
        cy,
        cosT: Math.cos(angleRad),
        sinT: Math.sin(angleRad),
        halfW: (maxX - minX) / 2 + halfPxW,
        halfH: (maxY - minY) / 2 + halfPxH,
      });
    } else {
      areas.push({
        kind: "aabb",
        minX: minX - halfPxW,
        maxX: maxX + halfPxW,
        minY: minY - halfPxH,
        maxY: maxY + halfPxH,
      });
    }
  }

  return areas;
}

function hitTestPanel(
  areas: PanelHitArea[],
  imgX: number,
  imgY: number
): number | null {
  for (let p = 0; p < areas.length; p++) {
    const area = areas[p];

    if (area.kind === "aabb") {
      if (
        imgX >= area.minX &&
        imgX <= area.maxX &&
        imgY >= area.minY &&
        imgY <= area.maxY
      ) {
        return p;
      }
    } else {
      const dx = imgX - area.cx;
      const dy = imgY - area.cy;
      // Inverse-rotate the point into the panel's own (unrotated) local
      // space — the transpose of the rotation matrix used to draw it.
      const localX = dx * area.cosT + dy * area.sinT;
      const localY = -dx * area.sinT + dy * area.cosT;

      if (Math.abs(localX) <= area.halfW && Math.abs(localY) <= area.halfH) {
        return p;
      }
    }
  }

  return null;
}

function panelTooltipText(info: PanelInfo, bearingDeg?: number): string {
  const lines = [
    `Panel ${info.panel}`,
    `Matrix ${info.width}×${info.height}`,
    `Controller ${info.controller}`,
    `Wiring ${info.wiring}`,
  ];

  if (bearingDeg != null) {
    lines.push(`Bearing ${Math.round(bearingDeg)}°`);
  }

  return lines.join("\n");
}

function createPanelTooltip(): HTMLDivElement {
  const tooltip = document.createElement("div");
  tooltip.style.position = "fixed";
  tooltip.style.pointerEvents = "none";
  tooltip.style.zIndex = "9999";
  tooltip.style.display = "none";
  tooltip.style.background = "rgba(17, 17, 17, 0.92)";
  tooltip.style.color = "#f5f5f5";
  tooltip.style.font = "12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace";
  tooltip.style.padding = "6px 9px";
  tooltip.style.borderRadius = "6px";
  tooltip.style.boxShadow = "0 2px 8px rgba(0, 0, 0, 0.4)";
  tooltip.style.whiteSpace = "pre";
  document.body.appendChild(tooltip);
  return tooltip;
}

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
    let panelHitAreas: PanelHitArea[] = [];
    let transform = { offsetX: 0, offsetY: 0, scale: 1 };

    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }

    const tooltip = createPanelTooltip();

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

      const fitScale = Math.min(
        canvas.width / layout.imageSize[0],
        canvas.height / layout.imageSize[1]
      );

      // Generic development views are never enlarged past 1:1, so a small
      // installation is not blown up across a monitor. A layout that exists to
      // fill a box in a page asks for the plain fit instead.
      const scale =
        isGenericLayout && !layout.fill ? Math.min(1.0, fitScale) : fitScale;

      const offsetX = canvas.width / 2 - (layout.imageSize[0] / 2) * scale;
      const offsetY = canvas.height / 2 - (layout.imageSize[1] / 2) * scale;
      transform = { offsetX, offsetY, scale };

      ctx.translate(offsetX, offsetY);
      ctx.scale(scale, scale);

      const ringLayout = isRingLayout(layout);

      if (ringLayout) {
        drawRingPixels(ctx, layout, pixels, pixelOffset);
      } else {
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
      }

      if (isGenericLayout && !ringLayout) {
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
      panelHitAreas = computePanelHitAreas(newLayout);
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

    const hideTooltip = () => {
      tooltip.style.display = "none";
    };

    const onPointerMove = (event: PointerEvent) => {
      if (!layout || panelHitAreas.length === 0) {
        hideTooltip();
        return;
      }

      const rect = canvas.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) {
        hideTooltip();
        return;
      }

      const canvasX =
        ((event.clientX - rect.left) / rect.width) * canvas.width;
      const canvasY =
        ((event.clientY - rect.top) / rect.height) * canvas.height;
      const imgX = (canvasX - transform.offsetX) / transform.scale;
      const imgY = (canvasY - transform.offsetY) / transform.scale;

      const panelIndex = hitTestPanel(panelHitAreas, imgX, imgY);
      const info = panelIndex != null ? layout.panelInfo?.[panelIndex] : null;

      if (!info) {
        hideTooltip();
        return;
      }

      const bearingDeg = layout.panelRotations?.[panelIndex as number];
      tooltip.textContent = panelTooltipText(info, bearingDeg);
      tooltip.style.left = `${event.clientX + 14}px`;
      tooltip.style.top = `${event.clientY + 14}px`;
      tooltip.style.display = "block";
    };

    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerleave", hideTooltip);

    this._cleanup = () => {
      if (resizeTimer != null) {
        window.clearTimeout(resizeTimer);
      }
      resizeObserver.disconnect();
      window.removeEventListener("resize", onResize);
      canvas.removeEventListener("pointermove", onPointerMove);
      canvas.removeEventListener("pointerleave", hideTooltip);
      tooltip.remove();
    };
  }

  destroyed() {
    this._cleanup?.();
  }
}

export default makeHook(PixelsHook);
