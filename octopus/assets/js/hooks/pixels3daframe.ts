import { Hook, makeHook } from "phoenix_typed_hook";
import AFRAME from "aframe";
// `aframe-orbit-controls` accesses the globals `AFRAME` and `THREE` that
// A-Frame sets on `window` at load time — so the import order must stay
// AFRAME → orbit-controls.
import "aframe-orbit-controls";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";
import { Frame, RGB, rgbPixelsFromFrame } from "./shared/frame";
import { getHumanWorld, registerHumanComponents } from "./humanComponents";
import type { MockWorldObject, RadarTrack } from "./humanWorld";

/** A-Frame ships its own THREE (~r173). Never mix the npm `three` package here — duplicate runtime breaks `setObject3D` / materials. */
function getThree() {
  return (AFRAME as any).THREE;
}

const vertexShader = `
  varying vec2 vUv;
  varying vec3 vWorldPosition;

  void main() {
    vUv = uv;
    vWorldPosition = position;
    gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
  }
`;

const fragmentShader = `
  uniform sampler2D uLEDTexture;
  uniform float uMask;
  uniform float uMaskSmoothness;
  uniform float uMaskSize;
  varying vec2 vUv;

  void main() {
    vec2 texCoord = floor(vec2(vUv.x, 1.0 - vUv.y) * 8.0) / 8.0 + vec2(0.5 / 8.0);
    vec3 color = texture2D(uLEDTexture, texCoord).rgb;

    vec2 cellUv = fract(vec2(vUv.x, 1.0 - vUv.y) * 8.0);
    vec2 center = vec2(0.5, 0.5);
    float distance = length(cellUv - center);

    float circle = smoothstep(uMaskSize, uMaskSize - uMaskSmoothness, distance);
    float mask = mix(1.0, circle, uMask);

    gl_FragColor = vec4(color * mask, 1.0);
  }
`;

const skyVertexShader = `
  varying vec2 vUv;
  varying vec3 vWorldPosition;

  void main() {
    vUv = uv;
    vWorldPosition = position;
    gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
  }
`;

const skyFragmentShader = `
  varying vec2 vUv;
  varying vec3 vWorldPosition;

  // Simple hash function
  float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
  }

  // Star field - uses UV coordinates for truly fixed positioning
  float stars(vec2 uv) {
    float gridSize = 100.0;
    vec2 grid = floor(uv * gridSize);
    vec2 cellUV = fract(uv * gridSize);

    float jx = hash(grid + 0.1);
    float jy = hash(grid + 0.2);
    vec2 starPos = vec2(jx, jy);

    float starSeed = hash(grid);
    float isStar = step(0.70, starSeed);

    float dist = length(cellUV - starPos);
    float star = smoothstep(0.03, 0.0, dist) * isStar;

    return star * 1.5;
  }

  // Simple nebula - uses UV coordinates
  vec3 nebula(vec2 uv) {
    // Create a few large, stable nebula regions
    vec2 nebula1 = uv - vec2(0.3, 0.7);
    vec2 nebula2 = uv - vec2(0.8, 0.2);

    float dist1 = length(nebula1);
    float dist2 = length(nebula2);

    float nebula1_intensity = smoothstep(0.3, 0.0, dist1) * 0.1;
    float nebula2_intensity = smoothstep(0.2, 0.0, dist2) * 0.1;

    vec3 color1 = vec3(0.1, 0.2, 0.8); // Blue
    vec3 color2 = vec3(0.8, 0.1, 0.3); // Pink

    return color1 * nebula1_intensity + color2 * nebula2_intensity;
  }

  void main() {
    // Base night sky color
    vec3 skyColor = vec3(0.02, 0.03, 0.08);

    // Add stars
    float starField = stars(vUv);
    skyColor += vec3(starField);

    // Add nebula
    skyColor += nebula(vUv);

    // Add subtle gradient from horizon to zenith
    float gradient = pow(vUv.y, 0.3);
    skyColor = mix(skyColor, skyColor * 1.2, gradient);

    gl_FragColor = vec4(skyColor, 1.0);
  }
`;

let panelDiameter = 20;
const PANEL_DIAMETER_MIN = 10;
const PANEL_DIAMETER_MAX = 20;

function clampPanelDiameter(v: number): number {
  return Math.min(
    PANEL_DIAMETER_MAX,
    Math.max(PANEL_DIAMETER_MIN, Number(v))
  );
}

const buttonPoleHeight = 1.0;
const buttonPoleRadius = 0.05;
const buttonBaseHeight = 0.02;
let buttonPolesRadius = (panelDiameter / 2) - 2;
const PANEL_SIZE = 1.6;
const PANEL_DEPTH = 0.3;
const numPanels = 12;
const panels: any[] = [];
const pixels: RGB[] = Array(numPanels * 8 * 8).fill([0, 0, 0]);
let poleDiameter: number = 0.4;
let poleHeight: number = 0.4;
const textures: any[] = [];

/** Radar sensors: distance to center (m) via lil-gui; cone visualization; height via radarHeight */
let radarHeight = 4.5;
const RADAR_RADIUS_MIN_M = 0;
const RADAR_RADIUS_MAX_M = 8;
/** Arm length (m): at 0° tilt = horizontal distance of the chips from the Y axis. Default comes from Phoenix (`radar_arm_length_m`). */
let radarRadiusM = 3.0;
/** Radar chip at the arm end (replaces the black box): 5×5 cm base, 1 cm thick, green, sits on the underside of the arm. */
const RADAR_CHIP_W_M = 0.05;
const RADAR_CHIP_D_M = 0.05;
const RADAR_CHIP_H_M = 0.01;
const RADAR_CHIP_COLOR = "#22c55e";
/** Top edge of the central pedestal (platform); mast/arms start here. */
const PEDESTAL_TOP_Y_M = 0.5;
/** Central platform ("sofa/plate"): radius via GUI 0.5–3 m, default 2.5 m. */
let platformRadiusM = 2.5;
const PLATFORM_RADIUS_MIN_M = 0.5;
const PLATFORM_RADIUS_MAX_M = 3;
/** Tilt of the arms (and thus the chips/cones): arms tilt upward from the mast, one value for all. */
let radarTiltDeg = 15;
/** Toggle: semi-transparent blue cone meshes (`radar-cone-viz`) on each sensor */
let renderRadarCones = false;
/**
 * Toggle: sensor look direction (blue cone + yellow axis) independent of the
 * arm tilt. If true, the cone points straight down (−Y) no matter how far the
 * arm is tilted (counter-rotation against the `tilt` group).
 */
let radarConeStraightDown = true;
/**
 * Full opening angle of the radar spotlight (A-Frame `light.angle`, degrees).
 * The blue cone (`radar-cone-viz`) uses the same angle — half-angle = /2.
 */
const RADAR_SPOT_ANGLE_DEG = 120;
const RADAR_SPOT_HALF_ANGLE_DEG = RADAR_SPOT_ANGLE_DEG / 2;
/** Three.js SpotLight: intensity falls to 0 at this distance (m) */
const RADAR_SPOT_DISTANCE_M = 8;
/**
 * Number of sensors: one upward-tilting arm (spoke) per sensor from the mast.
 * Stays even in steps of 2 so the star is symmetric.
 */
const RADAR_COUNT_MIN = 4;
const RADAR_COUNT_MAX = 12;
const RADAR_COUNT_STEP = 2;
let radarCount = 6;
/** Central mast (below the radar boxes): diameter 5–50 cm, default comes from Phoenix (`mast_diameter_m`). */
let mastDiameterM = 0.35;
const MAST_DIAMETER_MIN_M = 0.05;
const MAST_DIAMETER_MAX_M = 0.5;
/** Beam star instead of a plate: cross-section (m) and a small central hub against beam crossings. */
const BEAM_HEIGHT_M = 0.06;
const BEAM_WIDTH_M = 0.1;

/** Leaning frustum on the platform around the mast: wide at the bottom, narrow at the top. Editable via GUI. */
let leanPostBottomR = 0.5;
let leanPostTopR = 0.1;
let leanPostHeight = 1.2;
const LEAN_POST_BASE_Y_M = 0.5;
const LEAN_POST_BOTTOM_R_MIN_M = 0.1;
const LEAN_POST_BOTTOM_R_MAX_M = 2.5;
const LEAN_POST_TOP_R_MIN_M = 0.02;
const LEAN_POST_TOP_R_MAX_M = 2.5;
const LEAN_POST_HEIGHT_MIN_M = 0.2;
const LEAN_POST_HEIGHT_MAX_M = 3.0;

function clampRadarCount(v: number): number {
  const snapped = Math.round(Number(v) / RADAR_COUNT_STEP) * RADAR_COUNT_STEP;
  return Math.min(RADAR_COUNT_MAX, Math.max(RADAR_COUNT_MIN, snapped));
}

let radarLilGui: GUI | null = null;

/**
 * Orbit cam: camera orbits `cameraTarget` via mouse (left-click = rotate,
 * right-click = pan, wheel = zoom). Values here are defaults; lil-gui
 * (camera folder) writes directly into these variables and calls
 * `applyCameraAttributes()`.
 */
let cameraFov = 60;
let cameraTargetY = 1.5;
let cameraMinDistance = 0.5;
let cameraMaxDistance = 60;
let cameraDamping = 0.1;
let cameraAutoRotate = false;
let cameraAutoRotateSpeed = 0.6;
let cameraEnablePan = true;
let cameraInitialPos: [number, number, number] = [0, 4, 14];

function applyCameraAttributes() {
  const cam = document.querySelector("#cameraRig") as any;
  if (!cam) return;
  cam.setAttribute("camera", `fov: ${cameraFov}; near: 0.05; far: 2000`);
  cam.setAttribute("orbit-controls", {
    target: { x: 0, y: cameraTargetY, z: 0 },
    enableDamping: true,
    dampingFactor: cameraDamping,
    rotateSpeed: 0.25,
    zoomSpeed: 0.6,
    panSpeed: 0.6,
    enablePan: cameraEnablePan,
    screenSpacePanning: true,
    minDistance: cameraMinDistance,
    maxDistance: cameraMaxDistance,
    minPolarAngle: 1,
    maxPolarAngle: 89,
    autoRotate: cameraAutoRotate,
    autoRotateSpeed: cameraAutoRotateSpeed,
    initialPosition: {
      x: cameraInitialPos[0],
      y: cameraInitialPos[1],
      z: cameraInitialPos[2],
    },
  });
}

/**
 * Footprint of the spherically-capped radar cone on the ground plane (y = 0).
 *
 * The `radar-cone-viz` cone has its apex at the sensor, half-angle θ and slant
 * length L (= spherical cap instead of a flat base). At tilt > 0 the ground
 * intersection is a conic (ellipse/parabola), additionally bounded by the cap.
 * We derive the longest chord (Ø max) and the extent perpendicular to it
 * (Ø min) from the sampled boundary points.
 *
 * Assumption: yaw = 0 (all sensors are parametrized identically, only rotated
 * in yaw — the footprint is invariant under yaw-rotation of the apex position).
 */
type RadarFootprint = {
  hasGroundHit: boolean;
  maxDiameterM: number;
  minDiameterM: number;
  groundReachMaxM: number;
  groundReachMinM: number;
};

/**
 * Ground footprint outline of a single radar cone. For each azimuth ψ around
 * the sensor's foot point (0, r0) we intersect the beam with the ground plane
 * (y = 0). A ground point is lit iff it lies within the spherical cap (distance
 * ≤ L from the apex) AND inside the cone half-angle θ, so the boundary radius
 * at ψ is min(R_cap, R_cone(ψ)). The cone condition is a quadratic in R.
 * Points come out ordered by ψ (no convex sorting needed) as (x, z) in the
 * sensor-local frame (yaw = 0, +z radially outward). Empty when the cone
 * never reaches the ground. Handles the straight-down case (tilt = 0) too,
 * where the footprint is a plain circle.
 */
function computeRadarConeGroundBoundary(): Array<[number, number]> {
  const { armTiltDeg, chipHeight, horizontalRadius } = computeRadarArmGeometry();
  const h = chipHeight;
  const r0 = horizontalRadius;
  if (h <= 0) return [];

  // Cone axis is vertical (tilt = 0) when the sensor is decoupled to point straight down.
  const coneTiltDeg = radarConeStraightDown ? 0 : armTiltDeg;
  const tiltRad = (coneTiltDeg * Math.PI) / 180;
  const theta = (RADAR_SPOT_HALF_ANGLE_DEG * Math.PI) / 180;
  const L = RADAR_SPOT_DISTANCE_M;
  // Apex sits at height h; if h ≥ L not even the spherical cap can touch the ground.
  if (h >= L) return [];
  const cosT = Math.cos(tiltRad);
  const sinT = Math.sin(tiltRad);
  const c = Math.cos(theta);
  const rCap = Math.sqrt(L * L - h * h);

  const pts: Array<[number, number]> = [];
  const steps = 240;
  for (let i = 0; i < steps; i++) {
    const psi = (i / steps) * 2 * Math.PI;
    // Cone boundary: (A²−c²)R² + 2AB·R + (B²−c²h²) = 0 with A = sinψ·sinT, B = h·cosT.
    const A = Math.sin(psi) * sinT;
    const B = h * cosT;
    const qa = A * A - c * c;
    const qb = 2 * A * B;
    const qc = B * B - c * c * h * h;
    let rCone = Infinity;
    const cand: number[] = [];
    if (Math.abs(qa) < 1e-9) {
      if (Math.abs(qb) > 1e-9) cand.push(-qc / qb);
    } else {
      const disc = qb * qb - 4 * qa * qc;
      if (disc >= 0) {
        const s = Math.sqrt(disc);
        cand.push((-qb + s) / (2 * qa));
        cand.push((-qb - s) / (2 * qa));
      }
    }
    for (const R of cand) {
      // Keep the nearest positive root on the downward-facing sheet.
      if (R > 1e-6 && B + A * R >= -1e-9 && R < rCone) rCone = R;
    }
    const R = Math.min(rCone, rCap);
    if (Number.isFinite(R)) pts.push([R * Math.cos(psi), r0 + R * Math.sin(psi)]);
  }
  return pts;
}

function computeRadarConeGroundFootprint(): RadarFootprint {
  const empty: RadarFootprint = {
    hasGroundHit: false,
    maxDiameterM: 0,
    minDiameterM: 0,
    groundReachMaxM: 0,
    groundReachMinM: 0,
  };
  const { horizontalRadius } = computeRadarArmGeometry();
  const r0 = horizontalRadius;
  const points = computeRadarConeGroundBoundary();

  if (points.length < 2) return empty;

  // Ø max: longest pairwise distance (O(N²), N ≈ 240 → fine, runs only on-change).
  let maxD2 = 0;
  let i1 = 0;
  let i2 = 0;
  for (let i = 0; i < points.length; i++) {
    for (let j = i + 1; j < points.length; j++) {
      const dx = points[i][0] - points[j][0];
      const dz = points[i][1] - points[j][1];
      const d2 = dx * dx + dz * dz;
      if (d2 > maxD2) {
        maxD2 = d2;
        i1 = i;
        i2 = j;
      }
    }
  }
  const major = Math.sqrt(maxD2);

  // Ø min: extent perpendicular to the major axis.
  const dx = points[i2][0] - points[i1][0];
  const dz = points[i2][1] - points[i1][1];
  const len = Math.sqrt(dx * dx + dz * dz) || 1;
  const ux = -dz / len;
  const uz = dx / len;
  let pMin = Infinity;
  let pMax = -Infinity;
  for (const p of points) {
    const proj = p[0] * ux + p[1] * uz;
    if (proj < pMin) pMin = proj;
    if (proj > pMax) pMax = proj;
  }
  const minor = pMax - pMin;

  // Reach from the sensor foot point (0, r0) on the ground.
  let reachMin = Infinity;
  let reachMax = -Infinity;
  for (const p of points) {
    const ddx = p[0];
    const ddz = p[1] - r0;
    const d = Math.sqrt(ddx * ddx + ddz * ddz);
    if (d < reachMin) reachMin = d;
    if (d > reachMax) reachMax = d;
  }

  return {
    hasGroundHit: true,
    maxDiameterM: major,
    minDiameterM: minor,
    groundReachMaxM: reachMax,
    groundReachMinM: reachMin,
  };
}

const radarFootprintInfo = {
  footprintMaxM: 0,
  footprintMinM: 0,
  reachMaxM: 0,
  reachMinM: 0,
  beamTopMaxM: 0,
};

/**
 * Highest point of the arms: top outer edge at the free arm end. The center
 * line ends at `chipHeight`; due to the arm thickness the top edge sits
 * BEAM_HEIGHT_M/2 higher perpendicular to the arm axis, projected vertically
 * by ·cos(tilt).
 */
function computeBeamTopMaxHeight(): number {
  const { armTiltDeg, chipHeight } = computeRadarArmGeometry();
  const tiltRad = (armTiltDeg * Math.PI) / 180;
  return chipHeight + (BEAM_HEIGHT_M / 2) * Math.cos(tiltRad);
}

function updateRadarFootprintInfo() {
  const fp = computeRadarConeGroundFootprint();
  const round3 = (v: number) => Math.round(v * 1000) / 1000;
  radarFootprintInfo.footprintMaxM = round3(fp.maxDiameterM);
  radarFootprintInfo.footprintMinM = round3(fp.minDiameterM);
  radarFootprintInfo.reachMaxM = round3(fp.groundReachMaxM);
  radarFootprintInfo.reachMinM = round3(fp.groundReachMinM);
  radarFootprintInfo.beamTopMaxM = round3(computeBeamTopMaxHeight());
}

/** Cone axis (from the sensor into the cone) as in `createRadarSensors`: R_y(yaw) · R_x(-tilt) · (0,-1,0). */
function radarConeAxisFromTiltYawDeg(tiltDeg: number, yawDeg: number) {
  const T = getThree();
  const ax = new T.Vector3(0, -1, 0);
  const xAxis = new T.Vector3(1, 0, 0);
  const yAxis = new T.Vector3(0, 1, 0);
  ax.applyAxisAngle(xAxis, T.MathUtils.degToRad(-tiltDeg));
  ax.applyAxisAngle(yAxis, T.MathUtils.degToRad(yawDeg));
  ax.normalize();
  return ax;
}

/** Max arm tilt; prevents `armLen`/`chipHeight` from diverging as tilt→90°. */
const RADAR_ARM_TILT_MAX_DEG = 85;

/**
 * Geometry of the upward-tilting arms: the mount at the mast is fixed at
 * `radarHeight` (= mast height). `radarRadiusM` is the **arm length** itself
 * (not the horizontal distance): at 0° tilt both coincide; at tilt t the
 * horizontal distance shrinks to `L·cos(t)` and the outer end rises to
 * `innerY + L·sin(t)`.
 * `armLen = radarRadiusM`, `horizontalRadius = L·cos(tilt)`,
 * `chipHeight = innerY + L·sin(tilt)`.
 */
function computeRadarArmGeometry(): {
  innerY: number;
  armTiltDeg: number;
  armLen: number;
  horizontalRadius: number;
  chipHeight: number;
} {
  const innerY = radarHeight;
  const armTiltDeg = Math.max(0, Math.min(RADAR_ARM_TILT_MAX_DEG, radarTiltDeg));
  const tiltRad = (armTiltDeg * Math.PI) / 180;
  const armLen = radarRadiusM;
  const horizontalRadius = radarRadiusM * Math.cos(tiltRad);
  const chipHeight = innerY + radarRadiusM * Math.sin(tiltRad);
  return { innerY, armTiltDeg, armLen, horizontalRadius, chipHeight };
}

type Param = {
  param: {
    diameter?: number;
    move?: [number, number];
    position?: [number, number];
    height?: number;
    pole_diameter?: number;
    foot_diameter?: number;
    button_diameter?: number;
    radar_count?: number;
    radar_height?: number;
    radar_tilt_deg?: number;
    radar_arm_length_m?: number;
    mast_diameter_m?: number;
    platform_radius_m?: number;
    lean_post_bottom_r?: number;
    lean_post_top_r?: number;
    lean_post_height?: number;
    render_radar_cones?: boolean;
    radar_cone_straight_down?: boolean;
  };
};

class Pixels3dAframeHook extends Hook {
  mounted() {
    console.log("Pixels3dAframeHook mounted");

    if (!AFRAME) {
      console.error('AFRAME not loaded!');
      return;
    }
    const canvas = this.el as HTMLCanvasElement;
    const id = canvas.id;
    this.registerShaders();
    this.createScene();
    this.handleEvent(`param:${id}`, ({ param: param }: Param) => {
      this.handleParams(param)
    });
    this.handleEvent(
      `radar_frame:${id}`,
      (payload: { device_id: number; frame_number: number; tracks: RadarTrack[] }) => {
        const world = getHumanWorld();
        if (!world) return;
        const tracks = Array.isArray(payload?.tracks) ? payload.tracks : [];
        world.setRadarTracksForDevice(Number(payload?.device_id), tracks);
      }
    );
    this.handleEvent(
      `mock_world:${id}`,
      (payload: { objects: MockWorldObject[] }) => {
        const world = getHumanWorld();
        if (!world) return;
        const objects = Array.isArray(payload?.objects) ? payload.objects : [];
        if (objects.length === 0) {
          world.clearMockWorld();
        } else {
          world.setMockWorldObjects(objects);
        }
      }
    );
    const events = ['frame:pixels-*', `frame:${id}`];
    events.forEach((event) => {
      this.handleEvent(event, ({ frame }: { frame: Frame }) => {
        for (let [i, pixel] of rgbPixelsFromFrame(frame).entries()) {
          pixels[i] = pixel;
        }
      });
    });
  }

  createScene() {
    const root = this.el as HTMLElement;
    root.style.minHeight = "100vh";
    root.style.width = "100%";

    const sceneEl = document.createElement("a-scene");
    sceneEl.setAttribute("embedded", "");
    sceneEl.setAttribute("vr-mode-ui", "enabled: false");
    sceneEl.style.display = "block";
    sceneEl.style.width = "100%";
    sceneEl.style.height = "100vh";

    this.registerComponents();
    const assetsEl = this.createAssets();
    sceneEl.appendChild(assetsEl);

    // Do not gate the scene on a-assets "loaded": missing/404 textures can prevent
    // that event from firing, leaving an empty embedded scene (beige page only).
    const panelsEl = this.createPanels();
    sceneEl.appendChild(panelsEl);

    // const buttonPolesEl = this.createButtonPoles();
    // sceneEl.appendChild(buttonPolesEl);

    const sky = this.createSky();
    sceneEl.appendChild(sky);

    const light = this.createLight();
    sceneEl.appendChild(light);

    const groundEl = this.createGround();
    sceneEl.appendChild(groundEl);

    const centralCylinder = this.createCentralCylinder();
    sceneEl.appendChild(centralCylinder);

    const leanPost = this.createLeanPost();
    sceneEl.appendChild(leanPost);

    this.applyRadarMastConstraints();

    const radarGround = this.createRadarGroundRings();
    sceneEl.appendChild(radarGround);

    const radarMast = this.createRadarMast();
    sceneEl.appendChild(radarMast);

    const radarSensors = this.createRadarSensors();
    sceneEl.appendChild(radarSensors);

    const radarFootprints = this.createRadarGroundFootprints();
    sceneEl.appendChild(radarFootprints);

    const humansRoot = this.createHumansRoot();
    sceneEl.appendChild(humansRoot);

    const cameraRig = this.createCameraRig();
    sceneEl.appendChild(cameraRig);

    this.el.appendChild(sceneEl);
    this.setupRadarGui();
  }

  setupRadarGui() {
    radarLilGui?.destroy();
    const gui = new GUI({ title: "Sim 3D" });
    radarLilGui = gui;

    // Bottom-left instead of the default top-right (top-right holds the Phoenix panel).
    const guiEl = gui.domElement as HTMLElement;
    guiEl.style.position = "fixed";
    guiEl.style.left = "8px";
    guiEl.style.right = "auto";
    guiEl.style.top = "auto";
    guiEl.style.bottom = "8px";
    // Collapsed by default.
    gui.close();

    // World geometry (panels/radar/platform/backrest) is now driven exclusively
    // via Phoenix (`Params.Sim3d` → `handleParams`). lil-gui only holds the
    // read-only info HUD and the client-side camera controls.
    updateRadarFootprintInfo();
    const infoFolder = gui.addFolder("Info (Boden-Footprint)");
    infoFolder
      .add(radarFootprintInfo, "footprintMaxM")
      .name("Ø max (m)")
      .listen()
      .disable();
    infoFolder
      .add(radarFootprintInfo, "footprintMinM")
      .name("Ø min (m)")
      .listen()
      .disable();
    infoFolder
      .add(radarFootprintInfo, "reachMaxM")
      .name("Reichweite max (m)")
      .listen()
      .disable();
    infoFolder
      .add(radarFootprintInfo, "reachMinM")
      .name("Reichweite min (m)")
      .listen()
      .disable();
    infoFolder
      .add(radarFootprintInfo, "beamTopMaxM")
      .name("Latten-Oberkante max (m)")
      .listen()
      .disable();
    infoFolder.open();

    const camParams = {
      cameraFov,
      cameraTargetY,
      cameraMinDistance,
      cameraMaxDistance,
      cameraDamping,
      cameraAutoRotate,
      cameraAutoRotateSpeed,
      cameraEnablePan,
      resetView: () => this.resetCameraView(),
    };
    const camFolder = gui.addFolder("Kamera");
    camFolder
      .add(camParams, "cameraFov", 20, 110, 1)
      .name("FOV (°)")
      .onChange((v: number) => {
        cameraFov = v;
        applyCameraAttributes();
      });
    camFolder
      .add(camParams, "cameraTargetY", 0, 6, 0.05)
      .name("Ziel-Höhe (m)")
      .onChange((v: number) => {
        cameraTargetY = v;
        applyCameraAttributes();
      });
    camFolder
      .add(camParams, "cameraMinDistance", 0.1, 5, 0.1)
      .name("Min Zoom")
      .onChange((v: number) => {
        cameraMinDistance = v;
        applyCameraAttributes();
      });
    camFolder
      .add(camParams, "cameraMaxDistance", 5, 200, 1)
      .name("Max Zoom")
      .onChange((v: number) => {
        cameraMaxDistance = v;
        applyCameraAttributes();
      });
    camFolder
      .add(camParams, "cameraDamping", 0, 0.4, 0.01)
      .name("Damping")
      .onChange((v: number) => {
        cameraDamping = v;
        applyCameraAttributes();
      });
    camFolder
      .add(camParams, "cameraEnablePan")
      .name("Pan (Rechtsklick)")
      .onChange((v: boolean) => {
        cameraEnablePan = !!v;
        applyCameraAttributes();
      });
    camFolder
      .add(camParams, "cameraAutoRotate")
      .name("Auto-Rotate")
      .onChange((v: boolean) => {
        cameraAutoRotate = !!v;
        applyCameraAttributes();
      });
    camFolder
      .add(camParams, "cameraAutoRotateSpeed", 0, 5, 0.1)
      .name("Auto-Rotate Speed")
      .onChange((v: number) => {
        cameraAutoRotateSpeed = v;
        applyCameraAttributes();
      });
    camFolder.add(camParams, "resetView").name("Ansicht zurücksetzen");
    camFolder.open();
  }

  /**
   * Resets the camera position to the default. It is not enough to just call
   * `setAttribute('position', …)` — `orbit-controls` holds the THREE state
   * internally. We remove the component and set it again, then `initialPosition`
   * takes effect again.
   */
  resetCameraView() {
    const cam = document.querySelector("#cameraRig") as any;
    if (!cam) return;
    cam.removeAttribute("orbit-controls");
    requestAnimationFrame(() => applyCameraAttributes());
  }

  destroyed() {
    radarLilGui?.destroy();
    radarLilGui = null;
  }

  /**
   * Orbit cam: a single entity carries both `camera` and `orbit-controls` (the
   * component requires `dependencies: ['camera']` and accesses
   * `getObject3D('camera')` of the same entity — no rig).
   * `look-controls`/`wasd-controls` are disabled automatically by the component
   * when present.
   */
  createCameraRig() {
    const cam = document.createElement("a-entity");
    cam.setAttribute("id", "cameraRig");
    cam.setAttribute("camera", `fov: ${cameraFov}; near: 0.05; far: 2000`);
    // Important: the entity stays at the origin. `orbit-controls` writes the
    // desired eye position into `getObject3D('camera').position` (local to this
    // entity). An additional `position` on the entity would shift the eye
    // position and distort the target.
    cam.setAttribute("orbit-controls", {
      target: { x: 0, y: cameraTargetY, z: 0 },
      enableDamping: true,
      dampingFactor: cameraDamping,
      rotateSpeed: 0.25,
      zoomSpeed: 0.6,
      panSpeed: 0.6,
      enablePan: cameraEnablePan,
      screenSpacePanning: true,
      minDistance: cameraMinDistance,
      maxDistance: cameraMaxDistance,
      minPolarAngle: 1,
      maxPolarAngle: 89,
      autoRotate: cameraAutoRotate,
      autoRotateSpeed: cameraAutoRotateSpeed,
      initialPosition: {
        x: cameraInitialPos[0],
        y: cameraInitialPos[1],
        z: cameraInitialPos[2],
      },
    } as any);
    return cam;
  }

  createAssets() {
    const assetsEl = document.createElement('a-assets');
    const albedo = document.createElement('img');
    albedo.setAttribute('id', 'ground-albedo');
    albedo.setAttribute('src', '/images/patchy-meadow1/patchy-meadow1_albedo.png');
    assetsEl.appendChild(albedo);
    const roughness = document.createElement('img');
    roughness.setAttribute('id', 'ground-roughness');
    roughness.setAttribute('src', '/images/patchy-meadow1/patchy-meadow1_roughness.png');
    assetsEl.appendChild(roughness);
    const normal = document.createElement('img');
    normal.setAttribute('id', 'ground-normal');
    normal.setAttribute('src', '/images/patchy-meadow1/patchy-meadow1_normal-ogl.png');
    assetsEl.appendChild(normal);
    const skysphere = document.createElement('img');
    skysphere.setAttribute('id', 'skysphere');
    skysphere.setAttribute('src', '/images/nog_250711.JPG');
    assetsEl.appendChild(skysphere);
    return assetsEl;
  }

  createButtonPoles() {
    const polesEl = document.createElement('a-entity');
    polesEl.setAttribute('id', 'button-poles');

    for (let i = 0; i < numPanels; i++) {
      const angle = (i / numPanels) * Math.PI * 2;
      const x = buttonPolesRadius * Math.sin(angle);
      const z = buttonPolesRadius * Math.cos(angle);
      const buzzerRadius = buttonPoleRadius - 0.01;
      // Pole (braun)
      const pole = document.createElement('a-cylinder');
      pole.setAttribute('radius', buttonPoleRadius.toString());
      pole.setAttribute('height', buttonPoleHeight.toString());
      pole.setAttribute('color', '#8B4513');
      pole.setAttribute('position', `${x} ${buttonPoleHeight / 2} ${z}`);
      polesEl.appendChild(pole);
      // Schwarzer Aufsatz
      const base = document.createElement('a-cylinder');
      base.setAttribute('radius', buttonPoleRadius.toString());
      base.setAttribute('height', buttonBaseHeight.toString());
      base.setAttribute('color', '#111');
      base.setAttribute('position', `${x} ${buttonPoleHeight + (buttonBaseHeight / 2)} ${z}`);
      polesEl.appendChild(base);
      // Roter Buzzer (Halbkugel)
      const buzzer = document.createElement('a-sphere');
      buzzer.setAttribute('radius', buzzerRadius.toString());
      buzzer.setAttribute('color', 'red');
      buzzer.setAttribute('position', `${x} ${buttonPoleHeight + buttonBaseHeight} ${z}`);
      buzzer.setAttribute('theta-start', '0');
      buzzer.setAttribute('theta-length', '90');
      // Spotlight im Buzzer
      const spotlight = document.createElement('a-light');
      spotlight.setAttribute('type', 'spot');
      spotlight.setAttribute('color', '#fff');
      spotlight.setAttribute('intensity', '3');
      spotlight.setAttribute('angle', '20');
      spotlight.setAttribute('distance', '0.2');
      spotlight.setAttribute('decay', '1');
      spotlight.setAttribute('position', `0 0.127 0`);
      spotlight.setAttribute('rotation', '-90 0 0'); // pointing up
      buzzer.appendChild(spotlight);
      polesEl.appendChild(buzzer);
    }
    return polesEl;
  }

  createGround() {
    const groundEl = document.createElement('a-plane');
    groundEl.setAttribute('rotation', '-90 0 0');
    groundEl.setAttribute('width', '2000');   // wie im Original
    groundEl.setAttribute('height', '2000');
    groundEl.setAttribute('position', '0 0 0');
    groundEl.setAttribute('material',
      'shader: standard; src: #ground-albedo; normalMap: #ground-normal; roughnessMap: #ground-roughness; normalScale: 1 1; metalness: 0.0; repeat: 1000 1000; side: double'
    );

    // Set repeat wrapping for textures so repeat works
    groundEl.addEventListener('materialtextureloaded', () => {
      const mesh = (groundEl as any).getObject3D('mesh');
      if (!mesh) return;
      ['map', 'normalMap', 'roughnessMap'].forEach((key) => {
        const tex = mesh.material[key];
        if (tex) {
          tex.wrapS = tex.wrapT = getThree().RepeatWrapping;
          tex.repeat.set(1000, 1000); // or desired repeat
          tex.needsUpdate = true;
        }
      });
      mesh.material.needsUpdate = true;
    });

    return groundEl;
  }

  createRadarGroundRings() {
    const g = document.createElement('a-entity');
    g.setAttribute('id', 'radar-ground-rings');
    const inner = document.createElement('a-ring');
    inner.setAttribute('position', '0 0.02 0');
    inner.setAttribute('rotation', '-90 0 0');
    const { horizontalRadius } = computeRadarArmGeometry();
    const rInner = Math.max(0, horizontalRadius - 0.01);
    const rOuter = horizontalRadius + 0.01;
    inner.setAttribute('radius-inner', rInner.toString());
    inner.setAttribute('radius-outer', rOuter.toString());
    inner.setAttribute(
      'material',
      'shader: flat; color: #222; opacity: 0.85; transparent: true; side: double'
    );
    g.appendChild(inner);
    const outer = document.createElement('a-ring');
    outer.setAttribute('id', 'radar-outer-ring');
    outer.setAttribute('position', '0 0.015 0');
    outer.setAttribute('rotation', '-90 0 0');
    const outerR = panelDiameter / 2;
    outer.setAttribute('radius-inner', (outerR - 0.04).toString());
    outer.setAttribute('radius-outer', (outerR + 0.04).toString());
    outer.setAttribute(
      'material',
      'shader: flat; color: #4488cc; opacity: 0.35; transparent: true; side: double'
    );
    g.appendChild(outer);
    return g;
  }

  /**
   * Ground footprint of the radar cones: per sensor a yellow outline plus a
   * faint yellow fill exactly where that cone cuts the ground plane (y = 0).
   * Only rendered while the cones are visible (`renderRadarCones`). Geometry is
   * built in the sensor-local frame (yaw = 0, +z radial) and yaw-rotated per
   * sensor — identical placement to `createRadarSensors`.
   */
  createRadarGroundFootprints() {
    const root = document.createElement('a-entity');
    root.setAttribute('id', 'radar-ground-footprints');
    if (!renderRadarCones) return root;

    const boundary = computeRadarConeGroundBoundary();
    if (boundary.length < 3) return root;

    const T = getThree();
    const n = clampRadarCount(radarCount);
    const y = 0.03;
    const FOOTPRINT_COLOR = 0xffee00;

    // Centroid for the fill's triangle fan.
    let cx = 0;
    let cz = 0;
    for (const p of boundary) {
      cx += p[0];
      cz += p[1];
    }
    cx /= boundary.length;
    cz /= boundary.length;

    // Fill: triangle fan from the centroid (footprint is convex).
    const fillPos: number[] = [];
    for (let i = 0; i < boundary.length; i++) {
      const a = boundary[i];
      const b = boundary[(i + 1) % boundary.length];
      fillPos.push(cx, y, cz, a[0], y, a[1], b[0], y, b[1]);
    }
    const fillGeo = new T.BufferGeometry();
    fillGeo.setAttribute(
      'position',
      new T.Float32BufferAttribute(fillPos, 3)
    );
    const fillMat = new T.MeshBasicMaterial({
      color: FOOTPRINT_COLOR,
      transparent: true,
      opacity: 0.15,
      depthWrite: false,
      side: T.DoubleSide,
    });

    // Outline: closed line along the boundary, nudged up slightly to avoid z-fighting.
    const linePts = boundary.map(
      (p) => new T.Vector3(p[0], y + 0.002, p[1])
    );
    const lineGeo = new T.BufferGeometry().setFromPoints(linePts);
    const lineMat = new T.LineBasicMaterial({ color: FOOTPRINT_COLOR });

    for (let i = 0; i < n; i++) {
      const yawDeg = T.MathUtils.radToDeg((i / n) * Math.PI * 2);
      const host = document.createElement('a-entity');
      host.setAttribute('rotation', `0 ${yawDeg} 0`);
      const group = new T.Group();
      group.add(new T.Mesh(fillGeo, fillMat));
      group.add(new T.LineLoop(lineGeo, lineMat));
      host.setObject3D('mesh', group);
      root.appendChild(host);
    }
    return root;
  }

  /**
   * Circle of the radar boxes: radius at least the mast radius (distance ≥ mast-diameter/2).
   * @returns true if radarRadiusM was adjusted (GUI may need to be rebuilt)
   */
  applyRadarMastConstraints(): boolean {
    const rMin = mastDiameterM / 2;
    const prev = radarRadiusM;
    radarRadiusM = Math.max(rMin, Math.min(RADAR_RADIUS_MAX_M, radarRadiusM));
    return Math.abs(prev - radarRadiusM) > 1e-9;
  }

  /**
   * Central mast (#8B4513) from the pedestal (0.5 m) up to the hub (`innerY`),
   * where the upward-tilting arms converge. The arms themselves (one per sensor)
   * and the chips are built in `createRadarSensors`, because they share the same
   * tilt per sensor.
   */
  createRadarMast() {
    const holder = document.createElement("a-entity");
    holder.setAttribute("id", "radar-mast");
    const { innerY } = computeRadarArmGeometry();

    const mastBodyH = Math.max(0, innerY - PEDESTAL_TOP_Y_M);
    if (mastBodyH > 1e-6) {
      const cyl = document.createElement("a-cylinder");
      cyl.setAttribute("radius", (mastDiameterM / 2).toString());
      cyl.setAttribute("height", mastBodyH.toString());
      cyl.setAttribute("color", "#8B4513");
      cyl.setAttribute("roughness", "0.65");
      cyl.setAttribute("position", `0 ${PEDESTAL_TOP_Y_M + mastBodyH / 2} 0`);
      holder.appendChild(cyl);
    }

    // Central hub where the arms converge.
    const hubR = Math.max(mastDiameterM / 2, BEAM_WIDTH_M * 0.9);
    const hub = document.createElement("a-cylinder");
    hub.setAttribute("radius", hubR.toString());
    hub.setAttribute("height", (BEAM_HEIGHT_M * 1.5).toString());
    hub.setAttribute("color", "#7a3d11");
    hub.setAttribute("roughness", "0.7");
    hub.setAttribute("position", `0 ${innerY} 0`);
    holder.appendChild(hub);
    return holder;
  }

  /**
   * One arm per sensor, tilting upward from the mast (hub, `innerY`) to the
   * outer end. At the outer end, on the underside (facing the ground), sits the
   * green radar chip; the cone extends from the chip underside along the arm's
   * underside normal (down/outward). Pivot (yaw) → tilt (arm tilt) →
   * arm/chip/cone share the same transform.
   */
  createRadarSensors() {
    const root = document.createElement('a-entity');
    root.setAttribute('id', 'radar-sensors');
    const n = clampRadarCount(radarCount);
    const T = getThree();
    const { innerY, armTiltDeg, armLen } = computeRadarArmGeometry();
    const chipY = -(BEAM_HEIGHT_M / 2 + RADAR_CHIP_H_M / 2);
    const chipZ = armLen - RADAR_CHIP_D_M / 2;
    for (let i = 0; i < n; i++) {
      const angle = (i / n) * Math.PI * 2;
      // +Z radially outward (without +180 — otherwise sensors point to the center)
      const yawDeg = T.MathUtils.radToDeg(angle);
      const pivot = document.createElement('a-entity');
      pivot.setAttribute('position', `0 ${innerY} 0`);
      pivot.setAttribute('rotation', `0 ${yawDeg} 0`);
      const tilt = document.createElement('a-entity');
      // -armTiltDeg about X: the +Z end (outer) goes up, the underside normal
      // points down/outward (= cone axis), chip on this underside.
      tilt.setAttribute('rotation', `${-armTiltDeg} 0 0`);

      // Arm: lies along +Z, inner end at the hub, outer end at the chip.
      const arm = document.createElement('a-box');
      arm.setAttribute('width', BEAM_WIDTH_M.toString());
      arm.setAttribute('height', BEAM_HEIGHT_M.toString());
      arm.setAttribute('depth', armLen.toString());
      arm.setAttribute('color', '#8B4513');
      arm.setAttribute('roughness', '0.65');
      arm.setAttribute('position', `0 0 ${armLen / 2}`);
      tilt.appendChild(arm);

      // Green chip on the underside of the arm end (facing the ground).
      const chip = document.createElement('a-box');
      chip.setAttribute('width', RADAR_CHIP_W_M.toString());
      chip.setAttribute('height', RADAR_CHIP_H_M.toString());
      chip.setAttribute('depth', RADAR_CHIP_D_M.toString());
      chip.setAttribute('color', RADAR_CHIP_COLOR);
      chip.setAttribute('roughness', '0.4');
      chip.setAttribute('position', `0 ${chipY} ${chipZ}`);
      tilt.appendChild(chip);

      if (renderRadarCones) {
        const coneHost = document.createElement('a-entity');
        // Apex at the chip underside; opening in -Y = arm tilt.
        coneHost.setAttribute('position', `0 ${chipY - RADAR_CHIP_H_M / 2} ${chipZ}`);
        // For "straight down", counter-rotate against the tilt group
        // (+armTiltDeg about X) so the cone axis points to −Y in world space.
        if (radarConeStraightDown) {
          coneHost.setAttribute('rotation', `${armTiltDeg} 0 0`);
        }
        coneHost.setAttribute(
          'radar-cone-viz',
          `length: ${RADAR_SPOT_DISTANCE_M}; halfAngleDeg: ${RADAR_SPOT_HALF_ANGLE_DEG}`
        );
        // No a-light spot: it would tint other meshes (mast, ground) blue too; the effect
        // now comes only from the semi-transparent cone mesh (radar-cone-viz), not from scene lighting.
        tilt.appendChild(coneHost);
      }

      pivot.appendChild(tilt);
      root.appendChild(pivot);
    }
    return root;
  }

  createCentralCylinder() {
    const cyl = document.createElement('a-cylinder');
    cyl.setAttribute('id', 'central-platform');
    cyl.setAttribute('radius', platformRadiusM.toString());
    cyl.setAttribute('height', '0.5');
    cyl.setAttribute('position', '0 0.25 0');
    cyl.setAttribute('color', '#8B4513');
    return cyl;
  }

  updateCentralCylinder() {
    const old = document.querySelector('#central-platform');
    const sceneEl = document.querySelector('a-scene');
    old?.parentNode?.removeChild(old);
    if (sceneEl) sceneEl.appendChild(this.createCentralCylinder());
  }

  /**
   * Leaning frustum around the mast: `a-cylinder` exposes only one radius,
   * hence `geometry: cone` with `radiusBottom` ≠ `radiusTop`. Sits centered on
   * the platform (top y=0.5), the mast grows further up through the hollow
   * interior.
   */
  createLeanPost() {
    const post = document.createElement('a-entity');
    post.setAttribute('id', 'lean-post');
    post.setAttribute(
      'geometry',
      `primitive: cone; radiusBottom: ${leanPostBottomR}; radiusTop: ${leanPostTopR}; height: ${leanPostHeight}; segmentsRadial: 48; openEnded: false`
    );
    post.setAttribute('material', 'color: #8B4513; roughness: 0.7');
    post.setAttribute(
      'position',
      `0 ${LEAN_POST_BASE_Y_M + leanPostHeight / 2} 0`
    );
    return post;
  }

  updateLeanPost() {
    const old = document.querySelector('#lean-post');
    const sceneEl = document.querySelector('a-scene');
    old?.parentNode?.removeChild(old);
    if (sceneEl) sceneEl.appendChild(this.createLeanPost());
  }

  createHumansRoot() {
    const root = document.createElement('a-entity');
    root.setAttribute('id', 'humans-root');
    root.setAttribute('humans-root', '');
    return root;
  }

  createLight() {
    // Directional light like 5 PM: warm, at an angle from above (southwest)
    const sun = document.createElement('a-entity');
    sun.setAttribute('light', 'type: directional; color: #ffd9a0; intensity: 1.1; castShadow: true');
    // Position: at an angle from above, southwest
    sun.setAttribute('position', '-10 20 -10');
    sun.setAttribute('rotation', '-45 -45 0');
    return sun;
  }

  createSky() {
    const skyEl = document.createElement('a-sky');
    skyEl.setAttribute('src', '/images/nog_250711.JPG')
    skyEl.setAttribute('scale', '-0.028 0.028 0.028');
    skyEl.setAttribute('position', '0 1.847 0');
    return skyEl;
  }

  createPanels() {
    panels.length = 0;
    textures.length = 0;
    const panelsEl = document.createElement('a-entity') as any;
    panelsEl.setAttribute('id', 'panels');
    for (let i = 0; i < numPanels; i++) {
      const angle = (i / numPanels) * Math.PI * 2;
      const group = document.createElement('a-entity') as any;
      group.object3D.position.set(
        (panelDiameter / 2) * Math.sin(angle),
        0,
        (panelDiameter / 2) * Math.cos(angle)
      );
      group.object3D.rotation.y = angle + Math.PI;
      // 8x8 texture
      const size = 8;
      const data = new Uint8Array(size * size * 4);
      for (let k = 0; k < size * size; k++) {
        data[k * 4 + 0] = 255; // R
        data[k * 4 + 1] = 0;   // G
        data[k * 4 + 2] = 0;   // B
        data[k * 4 + 3] = 255; // A
      }
      const T = getThree();
      const texture = new T.DataTexture(data, size, size, T.RGBAFormat);
      texture.needsUpdate = true;
      textures.push(texture);
      // Front plane
      const front = document.createElement('a-entity');
      front.setAttribute('geometry', `primitive: plane; height: ${PANEL_SIZE}; width: ${PANEL_SIZE}`);
      front.setAttribute('material', 'shader: led-shader; transparent: true');
      front.setAttribute('led-panel', `textureIndex: ${i}; side: front`);
      front.setAttribute('position', `0 ${poleHeight + PANEL_SIZE/2} ${PANEL_DEPTH/2 + 0.1}`);
      // Back plane
      const back = document.createElement('a-entity');
      back.setAttribute('geometry', `primitive: plane; height: ${PANEL_SIZE}; width: ${PANEL_SIZE}`);
      back.setAttribute('material', 'shader: led-shader; transparent: true');
      back.setAttribute('led-panel', `textureIndex: ${i}; side: back`);
      back.setAttribute('rotation', `0 180 0`);
      back.setAttribute('position', `0 ${poleHeight + PANEL_SIZE/2} ${-(PANEL_DEPTH/2 + 0.1)}`);
      // Center box (optional, as the panel "body")
      const center = document.createElement('a-entity');
      center.setAttribute('geometry', `primitive: box; height: ${PANEL_SIZE}; width: ${PANEL_SIZE}; depth: ${PANEL_DEPTH}`);
      center.setAttribute('material', 'color: #fff; roughness: 0.4');
      center.setAttribute('position', `0 ${poleHeight + PANEL_SIZE/2} 0`);
      // Poles
      const poleLeft = document.createElement('a-cylinder');
      poleLeft.setAttribute('radius', (poleDiameter / 2).toString());
      poleLeft.setAttribute('height', poleHeight.toString());
      poleLeft.setAttribute('color', '#8B4513');
      poleLeft.setAttribute('position', `${-PANEL_SIZE/2 + poleDiameter/2} ${poleHeight/2} 0`);
      const poleRight = document.createElement('a-cylinder');
      poleRight.setAttribute('radius', (poleDiameter / 2).toString());
      poleRight.setAttribute('height', poleHeight.toString());
      poleRight.setAttribute('color', '#8B4513');
      poleRight.setAttribute('position', `${PANEL_SIZE/2 - poleDiameter/2} ${poleHeight/2} 0`);
      group.appendChild(center);
      group.appendChild(front);
      group.appendChild(back);
      group.appendChild(poleLeft);
      group.appendChild(poleRight);
      panelsEl.appendChild(group);
    }
    panelsEl.setAttribute('update-panel-textures', '');
    return panelsEl;
  }

  handleParams(param: Param["param"]) {
    if (param.diameter !== undefined && param.diameter !== null) {
      panelDiameter = clampPanelDiameter(param.diameter);
      this.updatePanels();
      this.updateRadarVisualization();
    }
    if (param.height) {
      poleHeight = param.height;
      this.updatePanels();
    }
    if (param.foot_diameter) {
      poleDiameter = param.foot_diameter;
      this.updatePanels();
    }
    if (param.button_diameter) {
      buttonPolesRadius = param.button_diameter / 2;
      this.updatePanels();
    }
    if (param.radar_count !== undefined && param.radar_count !== null) {
      radarCount = clampRadarCount(Number(param.radar_count));
      this.updateRadarVisualization();
    }
    if (param.radar_height !== undefined && param.radar_height !== null) {
      radarHeight = Number(param.radar_height);
      this.updateRadarVisualization();
    }
    if (param.radar_tilt_deg !== undefined && param.radar_tilt_deg !== null) {
      radarTiltDeg = Number(param.radar_tilt_deg);
      this.updateRadarVisualization();
    }
    if (param.radar_arm_length_m !== undefined && param.radar_arm_length_m !== null) {
      radarRadiusM = Math.min(
        RADAR_RADIUS_MAX_M,
        Math.max(RADAR_RADIUS_MIN_M, Number(param.radar_arm_length_m))
      );
      this.updateRadarVisualization();
    }
    if (param.mast_diameter_m !== undefined && param.mast_diameter_m !== null) {
      mastDiameterM = Math.min(
        MAST_DIAMETER_MAX_M,
        Math.max(MAST_DIAMETER_MIN_M, Number(param.mast_diameter_m))
      );
      this.updateRadarVisualization();
    }
    if (param.platform_radius_m !== undefined && param.platform_radius_m !== null) {
      platformRadiusM = Math.min(
        PLATFORM_RADIUS_MAX_M,
        Math.max(PLATFORM_RADIUS_MIN_M, Number(param.platform_radius_m))
      );
      this.updateCentralCylinder();
    }
    if (param.lean_post_bottom_r !== undefined && param.lean_post_bottom_r !== null) {
      leanPostBottomR = Math.min(
        LEAN_POST_BOTTOM_R_MAX_M,
        Math.max(LEAN_POST_BOTTOM_R_MIN_M, Number(param.lean_post_bottom_r))
      );
      this.updateLeanPost();
    }
    if (param.lean_post_top_r !== undefined && param.lean_post_top_r !== null) {
      leanPostTopR = Math.min(
        LEAN_POST_TOP_R_MAX_M,
        Math.max(LEAN_POST_TOP_R_MIN_M, Number(param.lean_post_top_r))
      );
      this.updateLeanPost();
    }
    if (param.lean_post_height !== undefined && param.lean_post_height !== null) {
      leanPostHeight = Math.min(
        LEAN_POST_HEIGHT_MAX_M,
        Math.max(LEAN_POST_HEIGHT_MIN_M, Number(param.lean_post_height))
      );
      this.updateLeanPost();
    }
    if (param.render_radar_cones !== undefined && param.render_radar_cones !== null) {
      renderRadarCones = !!param.render_radar_cones;
      this.updateRadarVisualization();
    }
    if (
      param.radar_cone_straight_down !== undefined &&
      param.radar_cone_straight_down !== null
    ) {
      radarConeStraightDown = !!param.radar_cone_straight_down;
      this.updateRadarVisualization();
    }
  }

  registerComponents() {
    registerHumanComponents();
    AFRAME.registerComponent('radar-cone-viz', {
      schema: {
        length: { type: 'number', default: 8 },
        halfAngleDeg: { type: 'number', default: RADAR_SPOT_HALF_ANGLE_DEG },
      },
      init: function (this: {
        el: any;
        data: { length: number; halfAngleDeg: number };
      }) {
        const T = getThree();
        // `length` is now the radius (slant length) from the sensor: all cone points
        // lie ≤ length from the apex. Instead of a flat base, a spherical cap
        // (sphere around the apex, radius = length) closes the cone → no straight cut-off.
        const L = this.data.length;
        const theta = T.MathUtils.degToRad(this.data.halfAngleDeg);
        const h = L * Math.cos(theta);
        const r = L * Math.sin(theta);

        const radialSegs = 32;
        const phiSegs = 12;

        const coneGeo = new T.CylinderGeometry(0, r, h, radialSegs, 1, true);
        const capGeo = new T.SphereGeometry(
          L,
          radialSegs,
          phiSegs,
          0,
          Math.PI * 2,
          0,
          theta
        );
        const mat = new T.MeshBasicMaterial({
          color: 0x66aaff,
          transparent: true,
          opacity: 0.16,
          depthWrite: false,
          side: T.DoubleSide,
        });
        // Tip (sensor) at the entity origin = center of the box; axis along -Y = same axis
        // as the 45° tilt group (no extra X flip — otherwise the cone would not point "with" the box).
        const group = new T.Group();
        const coneMesh = new T.Mesh(coneGeo, mat);
        coneMesh.position.y = -h / 2;
        group.add(coneMesh);
        // Sphere is centered on the apex; a 180° rotation about X turns the pole to -Y, so the rim
        // automatically lands at y=-h, radius=r (= cone rim).
        const capMesh = new T.Mesh(capGeo, mat);
        capMesh.rotation.x = Math.PI;
        group.add(capMesh);
        this.el.setObject3D('mesh', group);

        // Cone center line: from the tip (0) to the cap pole (-L), ~2 cm Ø, neon yellow
        const axisRadiusM = 0.01;
        const axisGeo = new T.CylinderGeometry(axisRadiusM, axisRadiusM, L, 16, 1, false);
        const axisMat = new T.MeshBasicMaterial({
          color: 0xdfff00,
          depthWrite: false,
          polygonOffset: true,
          polygonOffsetFactor: -1,
          polygonOffsetUnits: -1,
        });
        const axisMesh = new T.Mesh(axisGeo, axisMat);
        axisMesh.position.y = -L / 2;
        axisMesh.renderOrder = 1;
        this.el.setObject3D('coneAxis', axisMesh);
      },
      remove: function (this: { el: any }) {
        this.el.removeObject3D('mesh');
        this.el.removeObject3D('coneAxis');
      },
    });
    AFRAME.registerComponent('led-panel', {
      schema: {
        textureIndex: {type: 'int'},
        side: {type: 'string', default: 'front'}
      },
      init: function () {
        const mesh = this.el.getObject3D('mesh');
        if (!mesh) return;
        const T = getThree();
        let uniforms;
        if (this.data.side === 'front') {
          uniforms = {
            uLEDTexture: { value: textures[this.data.textureIndex] },
            uMask: { value: 0.2 },
            uMaskSmoothness: { value: 1.0 },
            uMaskSize: { value: 1.0 },
          };
        } else {
          uniforms = {
            uLEDTexture: { value: textures[this.data.textureIndex] },
            uMask: { value: 1.0 },
            uMaskSmoothness: { value: 0.05 },
            uMaskSize: { value: 0.1 },
          };
        }
        mesh.material = new T.ShaderMaterial({
          vertexShader: vertexShader,
          fragmentShader: fragmentShader,
          transparent: true,
          uniforms: uniforms
        });
      }
    });
    AFRAME.registerComponent('update-panel-textures', {
      tick: function () {
        for (let i = 0; i < numPanels; i++) {
          for (let j = 0; j < 64; j++) {
            const textureIdx = numPanels - i - 1;
            const pixelIdx = i * 64 + j;
            if (pixels[pixelIdx]) {
              const texture = textures[textureIdx];
              if (!texture || !texture.image) {
                console.warn('Texture or texture.image is undefined', textureIdx, texture);
                return;
              }
              const data = texture.image.data;
              data[j * 4] = pixels[pixelIdx][0];
              data[j * 4 + 1] = pixels[pixelIdx][1];
              data[j * 4 + 2] = pixels[pixelIdx][2];
              data[j * 4 + 3] = 255;
              texture.needsUpdate = true;
            }
          }
        }
      }
    });
  }

  registerShaders() {
    AFRAME.registerShader('led-shader', {
      vertexShader: vertexShader,
      fragmentShader: fragmentShader
    })
    AFRAME.registerShader('sky-shader', {
      vertexShader: skyVertexShader,
      fragmentShader: skyFragmentShader
    })
  }

  updatePanels() {
    panels.length = 0;
    textures.length = 0;
    const oldPanels = document.querySelector('#panels');
    const sceneEl = document.querySelector('a-scene');
    if (oldPanels) {
      oldPanels.parentNode?.removeChild(oldPanels);
    }
    const newPanels = this.createPanels();
    if (sceneEl) {
      sceneEl.appendChild(newPanels);
    }
  }

  updateRadarVisualization() {
    const sceneEl = document.querySelector('a-scene');
    if (!sceneEl) return;
    this.applyRadarMastConstraints();
    const oldRings = document.querySelector('#radar-ground-rings');
    const oldRadar = document.querySelector('#radar-sensors');
    const oldMast = document.querySelector('#radar-mast');
    const oldFootprints = document.querySelector('#radar-ground-footprints');
    oldRings?.parentNode?.removeChild(oldRings);
    oldRadar?.parentNode?.removeChild(oldRadar);
    oldMast?.parentNode?.removeChild(oldMast);
    oldFootprints?.parentNode?.removeChild(oldFootprints);
    sceneEl.appendChild(this.createRadarGroundRings());
    sceneEl.appendChild(this.createRadarMast());
    sceneEl.appendChild(this.createRadarSensors());
    sceneEl.appendChild(this.createRadarGroundFootprints());
    updateRadarFootprintInfo();
  }
}

export default makeHook(Pixels3dAframeHook);
