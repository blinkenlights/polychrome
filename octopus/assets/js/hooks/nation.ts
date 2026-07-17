import { Hook, makeHook } from "phoenix_typed_hook";
import { Frame, FrameBuffer, RGB } from "./shared/frame";

interface PanelPosition {
  x: number;        // world meters, east
  y: number;        // world meters, north
  theta_deg: number; // clockwise from north
}

interface WorldConfig {
  world_radius_m: number;
  platform_radius_m: number;
  panel_width_m: number;
  panel_height_m: number;   // face height (same axis as pixel rows)
  panel_grid_w: number;
  panel_grid_h: number;
  panels: PanelPosition[];
}

interface RadarTrack {
  x: number;
  y: number;
  vx: number;
  vy: number;
  opacity: number;
  color: string;
  merged: boolean;
  sensor_colors: string[];
}

// The world is displayed with 15% padding beyond the panel tips.
// Effective radius = ring radius + panel face height.
const OUTER_PADDING = 1.15;

function effectiveRadius(world: WorldConfig): number {
  return world.world_radius_m + world.panel_height_m;
}

// Grid dot radius in device pixels.
const GRID_DOT_RADIUS_PX = 2.5;

// Fixed track circle radius in world meters.
const TRACK_RADIUS_M = 0.6;

// Velocity arrow constants copied from RadarLive:
//   @velocity_scale = 40  vb-units per m/s
//   @velocity_max_len = 100  vb-units
//   @vb = 1000
const VELOCITY_VB_SCALE = 40;
const VELOCITY_VB_MAX = 100;
const VB = 1000;

// Pixel colour processing — same constants as pixels.ts.
const DESAT_AMOUNT = 0.15;
const BRIGHTEN_AMOUNT = 0.1;

function desaturate([r, g, b]: RGB, amount: number): RGB {
  const a = 1 - amount;
  const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return [l + (r - l) * a, l + (g - l) * a, l + (b - l) * a];
}

function brighten([r, g, b]: RGB, amount: number): RGB {
  return [
    r + (255 - r) * amount,
    g + (255 - g) * amount,
    b + (255 - b) * amount,
  ];
}

function processPixel(px: RGB): RGB {
  return brighten(desaturate(px, DESAT_AMOUNT), BRIGHTEN_AMOUNT);
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

function resizeCanvas(canvas: HTMLCanvasElement): boolean {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const w = Math.max(1, Math.round(rect.width * dpr));
  const h = Math.max(1, Math.round(rect.height * dpr));
  if (canvas.width === w && canvas.height === h) return false;
  canvas.width = w;
  canvas.height = h;
  return true;
}

// Returns true when the current DaisyUI/system theme is dark.
function isDarkTheme(): boolean {
  const theme = document.documentElement.getAttribute("data-theme") || "retro";
  // "light" is the only explicitly light DaisyUI theme in this app.
  return theme !== "light";
}

// Theme-specific colour palette for the static layer.
interface ThemeColors {
  bg: string;
  gridDot: string;
  center: string;
  platform: string;
  ring: string;
}

function themeColors(): ThemeColors {
  if (isDarkTheme()) {
    return {
      bg: "#111827",
      gridDot: "rgba(255,255,255,0.30)",   // clearly visible on near-black
      center:  "rgba(255,255,255,0.85)",   // bright white crosshair
      platform:"rgba(251,191,36,0.90)",    // bright amber
      ring:    "rgba(203,213,225,0.75)",   // light slate, prominent dashed ring
    };
  }
  return {
    bg: "#f3f4f6",
    gridDot: "rgba(0,0,0,0.18)",
    center:  "rgba(0,0,0,0.55)",
    platform:"rgba(180,83,9,0.75)",
    ring:    "rgba(75,85,99,0.5)",
  };
}

// Renders the static background layer (grid, center marker, platform circle,
// ring border) onto an OffscreenCanvas.  Called once on world-config changes,
// on canvas resize, and on theme change.
function buildStaticLayer(
  w: number,
  h: number,
  world: WorldConfig
): OffscreenCanvas {
  const offscreen = new OffscreenCanvas(w, h);
  const ctx = offscreen.getContext("2d")!;

  const colors = themeColors();
  const effR = effectiveRadius(world);
  const worldDiameter = effR * 2 * OUTER_PADDING;
  const scale = Math.min(w, h) / worldDiameter;
  const originX = w / 2;
  const originY = h / 2;

  // Fill background so the canvas is never transparent.
  ctx.fillStyle = colors.bg;
  ctx.fillRect(0, 0, w, h);

  const cx = (wx: number) => originX + wx * scale;
  const cy = (wy: number) => originY - wy * scale;

  // ── Grid: dots at every full-meter intersection ─────────────────────────
  {
    const lim = Math.ceil(effR * OUTER_PADDING);
    ctx.fillStyle = colors.gridDot;
    for (let mx = -lim; mx <= lim; mx++) {
      for (let my = -lim; my <= lim; my++) {
        if (Math.sqrt(mx * mx + my * my) > effR * OUTER_PADDING) continue;
        ctx.beginPath();
        ctx.arc(cx(mx), cy(my), GRID_DOT_RADIUS_PX, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  // ── Center marker (crosshair at world origin) ───────────────────────────
  {
    const arm = 14;
    ctx.strokeStyle = colors.center;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(cx(0) - arm, cy(0));
    ctx.lineTo(cx(0) + arm, cy(0));
    ctx.moveTo(cx(0), cy(0) - arm);
    ctx.lineTo(cx(0), cy(0) + arm);
    ctx.stroke();
  }

  // ── Platform circle (dashed amber) ─────────────────────────────────────
  {
    ctx.strokeStyle = colors.platform;
    ctx.lineWidth = 2;
    ctx.setLineDash([4, 6]);
    ctx.beginPath();
    ctx.arc(cx(0), cy(0), world.platform_radius_m * scale, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // ── Installation ring border (dashed) — marks the inner panel edge ─────
  {
    ctx.strokeStyle = colors.ring;
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 6]);
    ctx.beginPath();
    ctx.arc(cx(0), cy(0), world.world_radius_m * scale, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  return offscreen;
}

// Draws a filled pie chart split equally across `colors` at (x, y) with
// radius r.  A single color produces a full circle.  Mirrors the SVG
// pie_slices/4 logic from RadarLive.  Caller must set globalAlpha before
// calling; this function does not touch globalAlpha itself.
function drawPieChart(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  r: number,
  colors: string[]
): void {
  if (colors.length === 0) return;

  const step = (Math.PI * 2) / colors.length;
  const start = -Math.PI / 2;

  colors.forEach((color, i) => {
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.arc(x, y, r, start + i * step, start + (i + 1) * step);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  });

  // Subtle dark inner rim (same as RadarLive's stroke="black" stroke-opacity="0.3")
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.strokeStyle = "rgba(0,0,0,0.3)";
  ctx.lineWidth = 1;
  ctx.stroke();
}

class NationHook extends Hook {
  _cleanup?: () => void;

  mounted() {
    const canvas = this.el as HTMLCanvasElement;
    const id = canvas.id;

    let world: WorldConfig | null = null;
    let staticLayer: OffscreenCanvas | null = null;
    let pixels: RGB[] = [];
    const buffer = new FrameBuffer();
    let tracks: RadarTrack[] = [];
    let drawQueued = false;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const rebuildStaticLayer = () => {
      if (!world) return;
      staticLayer = buildStaticLayer(canvas.width, canvas.height, world);
    };

    // ─── draw ──────────────────────────────────────────────────────────────

    const draw = () => {
      drawQueued = false;
      if (!world) return;

      // Keep canvas buffer in sync with CSS size; rebuild static layer if
      // dimensions changed (same pattern as pixels.ts).
      if (resizeCanvas(canvas)) {
        rebuildStaticLayer();
      }
      if (!staticLayer) {
        rebuildStaticLayer();
      }
      if (!staticLayer) return;

      // Composite the pre-rendered static background in one call.
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(staticLayer, 0, 0);

      // World-to-canvas transform (world +Y = north = canvas up).
      const effR = effectiveRadius(world);
      const worldDiameter = effR * 2 * OUTER_PADDING;
      const scale = Math.min(canvas.width, canvas.height) / worldDiameter;
      const originX = canvas.width / 2;
      const originY = canvas.height / 2;

      const cx = (wx: number) => originX + wx * scale;
      const cy = (wy: number) => originY - wy * scale;

      // Velocity arrow scaling in world meters.
      const arrowScaleM = (VELOCITY_VB_SCALE / VB) * worldDiameter;
      const arrowMaxM = (VELOCITY_VB_MAX / VB) * worldDiameter;

      // ── LED panel pixels ───────────────────────────────────────────────
      {
        const { panel_width_m, panel_height_m, panel_grid_w, panel_grid_h } = world;
        const pixelW = (panel_width_m / panel_grid_w) * scale;
        const pixelH = (panel_height_m / panel_grid_h) * scale;
        const halfPanelW = (panel_width_m / 2) * scale;
        // Full radial extent of the panel face in canvas pixels.
        const panelHScale = panel_height_m * scale;
        const panelWScale = panel_width_m * scale;
        const pixelsPerPanel = panel_grid_w * panel_grid_h;
        const dark = isDarkTheme();

        world.panels.forEach((panel, p) => {
          const thetaRad = (panel.theta_deg * Math.PI) / 180;
          const panelCx = cx(panel.x);
          const panelCy = cy(panel.y);

          ctx.save();
          ctx.translate(panelCx, panelCy);
          // Clockwise rotation matches circular_layout.ex and pixels.ts.
          ctx.rotate(thetaRad);

          // Panel origin = inner face (ring circumference).
          // Pixels extend from Y = -panelHScale (outer) to Y = 0 (inner).
          const base = p * pixelsPerPanel;

          // Panel background — dark mode only, so off-pixels are visible as
          // a gray surface instead of blending into the black canvas.
          if (dark) {
            ctx.fillStyle = "rgba(128,128,128,0.5)";
            ctx.fillRect(-halfPanelW, -panelHScale, panelWScale, panelHScale);
          }

          for (let row = 0; row < panel_grid_h; row++) {
            for (let col = 0; col < panel_grid_w; col++) {
              // Skip when no frame data is available — lets the gray
              // background show through instead of covering it with black.
              const raw: RGB | undefined = pixels[base + row * panel_grid_w + col];
              if (!raw) continue;
              const [r, g, b] = processPixel(raw);
              ctx.fillStyle = `rgb(${Math.round(r)},${Math.round(g)},${Math.round(b)})`;
              ctx.fillRect(
                col * pixelW - halfPanelW,
                row * pixelH - panelHScale,
                pixelW,
                pixelH
              );
            }
          }

          // 1 px gap border around the panel matrix in both modes.
          {
            const gap = 1;
            ctx.strokeStyle = dark
              ? "rgba(255,255,255,0.55)"
              : "rgba(0,0,0,0.35)";
            ctx.lineWidth = 1;
            ctx.strokeRect(
              -halfPanelW - gap,
              -panelHScale - gap,
              panelWScale + gap * 2,
              panelHScale + gap * 2
            );
          }

          ctx.restore();
        });
      }

      // ── Radar tracks: velocity arrows + filled circles / pie charts ──────
      {
        const trackR = TRACK_RADIUS_M * scale;

        tracks.forEach((t) => {
          if (t.opacity <= 0) return;

          ctx.globalAlpha = t.opacity;

          const trackCx = cx(t.x);
          const trackCy = cy(t.y);

          const dvx = clamp(t.vx * arrowScaleM, -arrowMaxM, arrowMaxM);
          const dvy = clamp(t.vy * arrowScaleM, -arrowMaxM, arrowMaxM);
          const arrowLen = Math.sqrt(dvx * dvx + dvy * dvy);

          if (arrowLen > 0.001) {
            // Angle of the velocity vector in canvas space.
            const origEndX = cx(t.x + dvx);
            const origEndY = cy(t.y + dvy);
            const angle = Math.atan2(origEndY - trackCy, origEndX - trackCx);
            const headLen = clamp(trackR * 0.75, 6, 14);

            // Shift the whole arrow outward by trackR so the shaft starts
            // at the circle edge and the tip sits outside the circle.
            const offsetX = trackR * Math.cos(angle);
            const offsetY = trackR * Math.sin(angle);
            const arrowStartX = trackCx + offsetX;
            const arrowStartY = trackCy + offsetY;
            const arrowEndX   = origEndX + offsetX;
            const arrowEndY   = origEndY + offsetY;

            const shaftLen = Math.hypot(arrowEndX - arrowStartX, arrowEndY - arrowStartY);
            if (shaftLen > headLen) {
              ctx.strokeStyle = t.color;
              ctx.lineWidth = 2;
              ctx.beginPath();
              ctx.moveTo(arrowStartX, arrowStartY);
              ctx.lineTo(arrowEndX, arrowEndY);
              ctx.stroke();

              ctx.fillStyle = t.color;
              ctx.beginPath();
              ctx.moveTo(arrowEndX, arrowEndY);
              ctx.lineTo(
                arrowEndX - headLen * Math.cos(angle - Math.PI / 6),
                arrowEndY - headLen * Math.sin(angle - Math.PI / 6)
              );
              ctx.lineTo(
                arrowEndX - headLen * Math.cos(angle + Math.PI / 6),
                arrowEndY - headLen * Math.sin(angle + Math.PI / 6)
              );
              ctx.closePath();
              ctx.fill();
            }
          }

          if (t.merged) {
            // Fused track: pie chart of contributing sensor colors + amber
            // dashed ring (mirrors RadarLive's SVG rendering exactly).
            drawPieChart(ctx, trackCx, trackCy, trackR, t.sensor_colors);

            ctx.strokeStyle = "#f59e0b";
            ctx.lineWidth = 2.5;
            ctx.setLineDash([4, 3]);
            ctx.beginPath();
            ctx.arc(trackCx, trackCy, trackR + 3, 0, Math.PI * 2);
            ctx.stroke();
            ctx.setLineDash([]);
          } else {
            // Single-sensor track: solid filled circle.
            ctx.fillStyle = t.color;
            ctx.globalAlpha = t.opacity * 0.5;
            ctx.beginPath();
            ctx.arc(trackCx, trackCy, trackR, 0, Math.PI * 2);
            ctx.fill();

            ctx.strokeStyle = t.color;
            ctx.lineWidth = 1.5;
            ctx.globalAlpha = t.opacity;
            ctx.beginPath();
            ctx.arc(trackCx, trackCy, trackR, 0, Math.PI * 2);
            ctx.stroke();
          }
        });

        ctx.globalAlpha = 1;
      }
    };

    // ─── scheduling ────────────────────────────────────────────────────────

    const scheduleDraw = () => {
      if (drawQueued) return;
      drawQueued = true;
      window.requestAnimationFrame(draw);
    };

    // ─── initial sizing ────────────────────────────────────────────────────

    resizeCanvas(canvas);

    // ─── event listeners ───────────────────────────────────────────────────

    this.handleEvent(`world:${id}`, (cfg: WorldConfig) => {
      world = cfg;
      rebuildStaticLayer();
      scheduleDraw();
    });

    this.handleEvent(`frame:${id}`, ({ frame }: { frame: Frame }) => {
      buffer.apply(frame);
      pixels = buffer.toRGB();
      scheduleDraw();
    });

    this.handleEvent(`radar:${id}`, ({ tracks: newTracks }: { tracks: RadarTrack[] }) => {
      tracks = newTracks;
      scheduleDraw();
    });

    // ─── resize handling ───────────────────────────────────────────────────

    let resizeTimer: ReturnType<typeof setTimeout> | undefined;

    const onResize = () => {
      if (resizeTimer != null) clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        resizeTimer = undefined;
        if (resizeCanvas(canvas)) {
          rebuildStaticLayer();
          scheduleDraw();
        }
      }, 150);
    };

    const resizeObserver = new ResizeObserver(onResize);
    resizeObserver.observe(canvas);
    window.addEventListener("resize", onResize);

    // ─── theme change handling ─────────────────────────────────────────────
    // Rebuild static layer when the DaisyUI theme changes (data-theme attr).

    const themeObserver = new MutationObserver(() => {
      rebuildStaticLayer();
      scheduleDraw();
    });
    themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });

    this._cleanup = () => {
      if (resizeTimer != null) clearTimeout(resizeTimer);
      resizeObserver.disconnect();
      themeObserver.disconnect();
      window.removeEventListener("resize", onResize);
    };
  }

  destroyed() {
    this._cleanup?.();
  }
}

export default makeHook(NationHook);
