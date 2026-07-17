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
  panel_depth_m: number;
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
}

// The world is displayed with 10% padding around the installation radius.
const PADDING = 1.1;

// Grid dot radius in device pixels.
const GRID_DOT_RADIUS_PX = 2.5;

// Fixed track circle radius in world meters (~0.6 m matches RadarLive's
// @detection_fixed_r = 28 vb-units at a 1000-vb/22m world scale).
const TRACK_RADIUS_M = 0.6;

// Velocity arrow constants copied from RadarLive:
//   @velocity_scale = 40  vb-units per m/s
//   @velocity_max_len = 100  vb-units
//   @vb = 1000
// Converted to world meters: arrowScaleM = (40/1000) * worldDiameter
//                             arrowMaxM   = (100/1000) * worldDiameter
const VELOCITY_VB_SCALE = 40;
const VELOCITY_VB_MAX = 100;
const VB = 1000;

// Pixel colour processing — same constants as pixels.ts so the panels read
// identically to the standard simulator view.
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

// Renders the static background layer (grid, center marker, platform circle,
// ring border) onto an OffscreenCanvas that matches the given pixel dimensions.
// Called once on world-config changes and on every canvas resize.
function buildStaticLayer(
  w: number,
  h: number,
  world: WorldConfig
): OffscreenCanvas {
  const offscreen = new OffscreenCanvas(w, h);
  const ctx = offscreen.getContext("2d")!;

  const worldDiameter = world.world_radius_m * 2 * PADDING;
  const scale = Math.min(w, h) / worldDiameter;
  const originX = w / 2;
  const originY = h / 2;

  const cx = (wx: number) => originX + wx * scale;
  const cy = (wy: number) => originY - wy * scale;

  // ── Grid: dots at every full-meter intersection ─────────────────────────
  {
    const lim = Math.ceil(world.world_radius_m);
    ctx.fillStyle = "rgba(255,255,255,0.18)";
    for (let mx = -lim; mx <= lim; mx++) {
      for (let my = -lim; my <= lim; my++) {
        if (Math.sqrt(mx * mx + my * my) > world.world_radius_m * PADDING) continue;
        ctx.beginPath();
        ctx.arc(cx(mx), cy(my), GRID_DOT_RADIUS_PX, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  // ── Center marker (crosshair at world origin) ───────────────────────────
  {
    const arm = 12;
    ctx.strokeStyle = "rgba(255,255,255,0.55)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(cx(0) - arm, cy(0));
    ctx.lineTo(cx(0) + arm, cy(0));
    ctx.moveTo(cx(0), cy(0) - arm);
    ctx.lineTo(cx(0), cy(0) + arm);
    ctx.stroke();
  }

  // ── Platform circle (dashed amber) ─────────────────────────────────────
  {
    ctx.strokeStyle = "rgba(161,98,7,0.75)";
    ctx.lineWidth = 1.5;
    ctx.setLineDash([4, 6]);
    ctx.beginPath();
    ctx.arc(cx(0), cy(0), world.platform_radius_m * scale, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // ── Installation ring border (dashed gray) ──────────────────────────────
  {
    ctx.strokeStyle = "rgba(156,163,175,0.5)";
    ctx.lineWidth = 1.5;
    ctx.setLineDash([6, 6]);
    ctx.beginPath();
    ctx.arc(cx(0), cy(0), world.world_radius_m * scale, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  return offscreen;
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

    // Rebuild the static layer whenever world config or canvas size changes.
    const rebuildStaticLayer = () => {
      if (!world) return;
      staticLayer = buildStaticLayer(canvas.width, canvas.height, world);
    };

    // ─── draw ──────────────────────────────────────────────────────────────

    const draw = () => {
      drawQueued = false;
      if (!world || !staticLayer) return;

      ctx.clearRect(0, 0, canvas.width, canvas.height);

      // Composite the pre-rendered static background in one call.
      ctx.drawImage(staticLayer, 0, 0);

      // World-to-canvas transform (world +Y = north = canvas up).
      const worldDiameter = world.world_radius_m * 2 * PADDING;
      const scale = Math.min(canvas.width, canvas.height) / worldDiameter;
      const originX = canvas.width / 2;
      const originY = canvas.height / 2;

      // Helpers: world meters → canvas pixels.
      const cx = (wx: number) => originX + wx * scale;
      const cy = (wy: number) => originY - wy * scale;

      // Velocity arrow scaling in world meters.
      const arrowScaleM = (VELOCITY_VB_SCALE / VB) * worldDiameter;
      const arrowMaxM = (VELOCITY_VB_MAX / VB) * worldDiameter;

      // ── 5. LED panel pixels ────────────────────────────────────────────
      {
        const { panel_width_m, panel_depth_m, panel_grid_w, panel_grid_h } = world;
        const pixelW = (panel_width_m / panel_grid_w) * scale;
        const pixelH = (panel_depth_m / panel_grid_h) * scale;
        const halfPanelW = (panel_width_m / 2) * scale;
        const halfPanelH = (panel_depth_m / 2) * scale;
        const pixelsPerPanel = panel_grid_w * panel_grid_h;

        world.panels.forEach((panel, p) => {
          const thetaRad = (panel.theta_deg * Math.PI) / 180;
          const panelCx = cx(panel.x);
          const panelCy = cy(panel.y);

          ctx.save();
          ctx.translate(panelCx, panelCy);
          // Clockwise rotation matches circular_layout.ex and pixels.ts.
          ctx.rotate(thetaRad);

          const base = p * pixelsPerPanel;

          for (let row = 0; row < panel_grid_h; row++) {
            for (let col = 0; col < panel_grid_w; col++) {
              const raw: RGB = pixels[base + row * panel_grid_w + col] ?? [0, 0, 0];
              const [r, g, b] = processPixel(raw);
              ctx.fillStyle = `rgb(${Math.round(r)},${Math.round(g)},${Math.round(b)})`;
              ctx.fillRect(
                col * pixelW - halfPanelW,
                row * pixelH - halfPanelH,
                pixelW,
                pixelH
              );
            }
          }

          ctx.restore();
        });
      }

      // ── 6. Radar tracks: velocity arrows + filled circles ──────────────
      {
        const trackR = TRACK_RADIUS_M * scale;

        tracks.forEach((t) => {
          if (t.opacity <= 0) return;

          ctx.globalAlpha = t.opacity;

          const trackCx = cx(t.x);
          const trackCy = cy(t.y);

          // Velocity arrow (only when the track has meaningful speed).
          const dvx = clamp(t.vx * arrowScaleM, -arrowMaxM, arrowMaxM);
          const dvy = clamp(t.vy * arrowScaleM, -arrowMaxM, arrowMaxM);
          const arrowLen = Math.sqrt(dvx * dvx + dvy * dvy);

          if (arrowLen > 0.001) {
            const arrowEndX = cx(t.x + dvx);
            const arrowEndY = cy(t.y + dvy);
            const angle = Math.atan2(arrowEndY - trackCy, arrowEndX - trackCx);
            const headLen = clamp(trackR * 0.75, 6, 14);

            ctx.strokeStyle = t.color;
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(trackCx, trackCy);
            ctx.lineTo(arrowEndX, arrowEndY);
            ctx.stroke();

            // Arrowhead (filled triangle).
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

          // Track circle.
          ctx.fillStyle = t.color;
          ctx.beginPath();
          ctx.arc(trackCx, trackCy, trackR, 0, Math.PI * 2);
          ctx.fill();
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

    this._cleanup = () => {
      if (resizeTimer != null) clearTimeout(resizeTimer);
      resizeObserver.disconnect();
      window.removeEventListener("resize", onResize);
    };
  }

  destroyed() {
    this._cleanup?.();
  }
}

export default makeHook(NationHook);
