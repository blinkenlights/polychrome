import { Hook, makeHook } from "phoenix_typed_hook";
import AFRAME from "aframe";
// `aframe-orbit-controls` accesses the globals `AFRAME` and `THREE` that
// A-Frame sets on `window` at load time — so the import order must stay
// AFRAME → orbit-controls.
import "aframe-orbit-controls";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";
import { Frame, RGB, rgbPixelsFromFrame } from "./shared/frame";
import { getHumanWorld, registerHumanComponents } from "./humanComponents";
import { radarGlobalToAframeXZ, type MockWorldObject, type RadarTrack } from "./humanWorld";

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

const buttonPoleHeight = 1.0;
const buttonPoleRadius = 0.05;
const buttonBaseHeight = 0.02;
let buttonPolesRadius = 8;
/** Panel outer dimensions (m); default until overridden by the installation. */
let panelWidthM = 1.6;
let panelDepthM = 0.3;
let numPanels = 12;
const panels: any[] = [];
const pixels: RGB[] = Array(numPanels * 8 * 8).fill([0, 0, 0]);
let poleDiameter: number = 0.4;
let poleHeight: number = 0.4;
const textures: any[] = [];

/**
 * Radar sensors are placed at their real global poses coming from the
 * installation radar layout (`installation:<id>` event). Each sensor always
 * looks straight down (ceiling installation, no tilt).
 */
type SensorPose = {
  deviceId: number;
  angleDeg: number;
  rotationDeg: number;
  distanceCm: number;
  rangeCm: number;
  heightCm: number;
  xM: number;
  zM: number;
};
let sensorPoses: SensorPose[] = [];
type PanelSlot = {
  index: number;
  panelNumber: number;
  xM: number;
  zM: number;
  rotationY: number;
};
let panelSlots: PanelSlot[] = [];
/** Outer LED panel ring radius (m) and which 1-based panel faces north (+Z). */
let ringRadiusM = 10.0;
let northPanel = 1;
/** Radar chip at each sensor: 5×5 cm base, 1 cm thick, green. */
const RADAR_CHIP_W_M = 0.05;
const RADAR_CHIP_D_M = 0.05;
const RADAR_CHIP_H_M = 0.01;
const RADAR_CHIP_COLOR = "#22c55e";
/** Central radar mast, wooden hub disk, and slats to each sensor mount. */
const RADAR_MAST_HEIGHT_M = 4.2;
const RADAR_MAST_RADIUS_M = 0.1;
const RADAR_DISK_RADIUS_M = 0.3;
const RADAR_DISK_THICKNESS_M = 0.04;
const RADAR_SLAT_RADIUS_M = 0.02;
const RADAR_WOOD_COLOR = "#8B4513";
const RADAR_DISK_COLOR = "#a0522d";
/** Central platform ("sofa/plate"); radius from installation payload. */
let platformRadiusM = 2.25;
/** Toggle: semi-transparent blue coverage cone + yellow axis per sensor. */
let renderRadarCones = false;
/**
 * Full opening angle of the LD6001A (±60° azimuth/pitch → 120° cone). The blue
 * cone (`radar-cone-viz`) uses the same angle — half-angle = /2.
 */
const RADAR_SPOT_ANGLE_DEG = 120;
const RADAR_SPOT_HALF_ANGLE_DEG = RADAR_SPOT_ANGLE_DEG / 2;

/** Same hue palette as `radar_live.ex` `@hues` / `sensor_color/1`. */
const SENSOR_HUES = [0, 36, 72, 108, 144, 180, 216, 252, 288, 324];
const SENSOR_BODY_SATURATION = 70;
const SENSOR_BODY_LIGHTNESS = 75;
const PANEL_LABEL_COLOR = '#ffffff';
const PANEL_LABEL_BG = 'rgba(0, 0, 0, 0.88)';
const SENSOR_LABEL_BG = 'rgba(17, 24, 39, 0.82)';
const LABEL_OUTWARD_OFFSET_M = 0.28;
const LABEL_FONT =
  '700 15px/1.2 ui-monospace, SFMono-Regular, Menlo, monospace';

type SceneLabelKind = 'panel' | 'sensor';

type SceneLabel = {
  kind: SceneLabelKind;
  text: string;
  x: number;
  y: number;
  z: number;
  color: string;
};

const sceneLabels: SceneLabel[] = [];
let labelsOverlayEl: HTMLDivElement | null = null;
let labelsHookRoot: HTMLElement | null = null;

function clearSceneLabels(kind?: SceneLabelKind) {
  if (kind) {
    for (let i = sceneLabels.length - 1; i >= 0; i--) {
      if (sceneLabels[i]!.kind === kind) sceneLabels.splice(i, 1);
    }
  } else {
    sceneLabels.length = 0;
  }
}

function addSceneLabel(
  kind: SceneLabelKind,
  text: string,
  x: number,
  y: number,
  z: number,
  color: string,
) {
  sceneLabels.push({ kind, text, x, y, z, color });
}

function ensureLabelsOverlay(root: HTMLElement): HTMLDivElement {
  labelsHookRoot = root;
  if (getComputedStyle(root).position === 'static') {
    root.style.position = 'relative';
  }
  if (!labelsOverlayEl) {
    labelsOverlayEl = document.createElement('div');
    labelsOverlayEl.className = 'scene-labels-overlay';
    Object.assign(labelsOverlayEl.style, {
      position: 'absolute',
      inset: '0',
      pointerEvents: 'none',
      overflow: 'hidden',
      zIndex: '2',
    });
    root.appendChild(labelsOverlayEl);
  }
  return labelsOverlayEl;
}

function refreshSceneLabelsDom(root: HTMLElement) {
  const overlay = ensureLabelsOverlay(root);
  overlay.replaceChildren();
  for (const label of sceneLabels) {
    const el = document.createElement('div');
    el.className = `scene-label scene-label--${label.kind}`;
    el.textContent = label.text;
    el.style.position = 'absolute';
    el.style.transform = 'translate(-50%, -50%)';
    el.style.font = LABEL_FONT;
    el.style.color = label.color;
    el.style.padding = '3px 8px';
    el.style.borderRadius = '4px';
    el.style.whiteSpace = 'nowrap';
    el.style.visibility = 'hidden';
    if (label.kind === 'panel') {
      el.style.background = PANEL_LABEL_BG;
      el.style.border = '1.5px solid rgba(255, 255, 255, 0.35)';
      el.style.boxShadow = '0 1px 6px rgba(0, 0, 0, 0.55)';
      el.style.textShadow = '0 1px 2px rgba(0, 0, 0, 0.9)';
    } else {
      el.style.background = SENSOR_LABEL_BG;
    }
    el.dataset.x = String(label.x);
    el.dataset.y = String(label.y);
    el.dataset.z = String(label.z);
    overlay.appendChild(el);
  }
}

function syncSceneLabelsDom() {
  if (!labelsOverlayEl) return;
  const sceneEl = document.querySelector('a-scene') as any;
  const camEl = document.querySelector('#cameraRig') as any;
  if (!sceneEl?.canvas || !camEl) return;

  const T = getThree();
  const threeCam = camEl.getObject3D('camera');
  if (!threeCam) return;

  const canvas = sceneEl.canvas as HTMLCanvasElement;
  const canvasRect = canvas.getBoundingClientRect();
  const overlayRect = labelsOverlayEl.getBoundingClientRect();
  const offsetX = canvasRect.left - overlayRect.left;
  const offsetY = canvasRect.top - overlayRect.top;
  const w = canvasRect.width;
  const h = canvasRect.height;
  const pos = new T.Vector3();

  for (const child of labelsOverlayEl.children) {
    const el = child as HTMLDivElement;
    pos.set(Number(el.dataset.x), Number(el.dataset.y), Number(el.dataset.z));
    pos.project(threeCam);
    if (pos.z > 1) {
      el.style.visibility = 'hidden';
      continue;
    }
    el.style.left = `${(pos.x * 0.5 + 0.5) * w + offsetX}px`;
    el.style.top = `${(-pos.y * 0.5 + 0.5) * h + offsetY}px`;
    el.style.visibility = 'visible';
  }
}

function destroySceneLabels() {
  labelsOverlayEl?.remove();
  labelsOverlayEl = null;
  labelsHookRoot = null;
  sceneLabels.length = 0;
}

function sensorHue(deviceId: number): number {
  return SENSOR_HUES[(deviceId * 7) % SENSOR_HUES.length]!;
}

function sensorColor(deviceId: number): string {
  return `hsl(${sensorHue(deviceId)}, ${SENSOR_BODY_SATURATION}%, ${SENSOR_BODY_LIGHTNESS}%)`;
}

function deviceLetter(deviceId: number): string {
  return String.fromCharCode(64 + Math.max(1, deviceId));
}

/** Cylinder between two world-space points (local Y axis of `a-cylinder`). */
function createWoodSlat(
  x1: number,
  y1: number,
  z1: number,
  x2: number,
  y2: number,
  z2: number,
  radiusM: number,
  color: string,
): HTMLElement {
  const T = getThree();
  const start = new T.Vector3(x1, y1, z1);
  const end = new T.Vector3(x2, y2, z2);
  const dir = new T.Vector3().subVectors(end, start);
  const length = dir.length();
  const host = document.createElement('a-entity');
  if (length < 0.001) return host;

  const mid = new T.Vector3().addVectors(start, end).multiplyScalar(0.5);
  const quat = new T.Quaternion().setFromUnitVectors(
    new T.Vector3(0, 1, 0),
    dir.normalize(),
  );
  host.object3D.position.copy(mid);
  host.object3D.quaternion.copy(quat);

  const slat = document.createElement('a-cylinder');
  slat.setAttribute('radius', radiusM.toString());
  slat.setAttribute('height', length.toString());
  slat.setAttribute('color', color);
  slat.setAttribute('roughness', '0.78');
  host.appendChild(slat);
  return host;
}

/** Leaning frustum on the platform: wide at the bottom, narrow at the top. Editable via GUI. */
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
/** South of center (+Z = north / north_panel faces away) — matches radar top-down. */
let cameraInitialPos: [number, number, number] = [0, 4, -14];

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
 * Ground footprint of a straight-down radar cone: a circle whose radius is
 * limited by both the ±60° opening angle at the sensor height and the
 * configured detection range (`AT+RANGE`).
 */
function sensorGroundRadiusM(pose: SensorPose): number {
  const h = pose.heightCm / 100;
  const rangeM = pose.rangeCm / 100;
  const coneR = h * Math.tan((RADAR_SPOT_HALF_ANGLE_DEG * Math.PI) / 180);
  return Math.max(0, Math.min(rangeM, coneR));
}

/**
 * Sensor mount position on the ground plane (aframe X/Z). Uses server-computed
 * coordinates when present (matches radar_live sensor_position).
 */
function sensorGroundPos(pose: SensorPose): { x: number; z: number } {
  if (Number.isFinite(pose.xM) && Number.isFinite(pose.zM)) {
    return radarGlobalToAframeXZ(pose.xM, pose.zM);
  }
  const d = pose.distanceCm / 100;
  const a = (pose.angleDeg * Math.PI) / 180;
  return radarGlobalToAframeXZ(d * Math.cos(a), d * Math.sin(a));
}

function panelSlotForIndex(i: number): PanelSlot {
  const slot = panelSlots.find((p) => p.index === i);
  if (slot) return slot;

  const offset = ((i - (northPanel - 1)) % numPanels + numPanels) % numPanels;
  const angle = (offset / numPanels) * Math.PI * 2;
  const centerR = ringRadiusM + panelDepthM / 2;
  const { x, z } = radarGlobalToAframeXZ(
    centerR * Math.sin(angle),
    centerR * Math.cos(angle),
  );
  return {
    index: i,
    panelNumber: i + 1,
    xM: x,
    zM: z,
    rotationY: Math.atan2(x, z) + Math.PI,
  };
}

const radarFootprintInfo = {
  footprintDiameterM: 0,
  reachM: 0,
  sensorHeightM: 0,
};

function updateRadarFootprintInfo() {
  const round3 = (v: number) => Math.round(v * 1000) / 1000;
  const pose = sensorPoses[0];

  if (!pose) {
    radarFootprintInfo.footprintDiameterM = 0;
    radarFootprintInfo.reachM = 0;
    radarFootprintInfo.sensorHeightM = 0;
    return;
  }

  const r = sensorGroundRadiusM(pose);
  radarFootprintInfo.footprintDiameterM = round3(2 * r);
  radarFootprintInfo.reachM = round3(r);
  radarFootprintInfo.sensorHeightM = round3(pose.heightCm / 100);
}

type InstallationPayload = {
  ring_radius_m?: number | null;
  num_panels?: number;
  north_panel?: number;
  platform_radius_m?: number | null;
  panel_width_m?: number | null;
  panel_depth_m?: number | null;
  panels?: Array<{
    index: number;
    panel_number: number;
    x_m: number;
    z_m: number;
    rotation_y: number;
  }>;
  sensors?: Array<{
    device_id?: number;
    angle_deg: number;
    rotation_deg?: number;
    distance_cm: number;
    range_cm: number;
    height_cm: number;
    x_m?: number;
    z_m?: number;
  }>;
};

type Param = {
  param: {
    move?: [number, number];
    position?: [number, number];
    height?: number;
    pole_diameter?: number;
    foot_diameter?: number;
    button_diameter?: number;
    lean_post_bottom_r?: number;
    lean_post_top_r?: number;
    lean_post_height?: number;
    render_radar_cones?: boolean;
  };
};

class Pixels3dAframeHook extends Hook {
  mounted() {
    console.log("Pixels3dAframeHook mounted");

    if (!AFRAME) {
      console.error('AFRAME not loaded!');
      return;
    }
    const root = this.el as HTMLElement;
    const id = root.id;

    this.handleEvent(`param:${id}`, ({ param: param }: Param) => {
      this.handleParams(param)
    });
    this.handleEvent(`installation:${id}`, (payload: InstallationPayload) => {
      this.handleInstallation(payload);
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

    const embedded = root.dataset.installation;
    if (embedded) {
      try {
        this.applyInstallationState(JSON.parse(embedded));
      } catch (error) {
        console.warn("Pixels3dAframe: failed to parse data-installation", error);
      }
    }

    this.createScene();
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

    this.registerShaders();
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

    const radarGround = this.createRadarGroundRings();
    sceneEl.appendChild(radarGround);

    const radarSensors = this.createRadarSensors();
    sceneEl.appendChild(radarSensors);

    const radarFootprints = this.createRadarGroundFootprints();
    sceneEl.appendChild(radarFootprints);

    const humansRoot = this.createHumansRoot();
    sceneEl.appendChild(humansRoot);

    const cameraRig = this.createCameraRig();
    sceneEl.appendChild(cameraRig);

    this.el.appendChild(sceneEl);
    refreshSceneLabelsDom(root);
    sceneEl.setAttribute('html-labels-sync', '');
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

    // Panel ring, radar poses, and platform come from the installation payload;
    // lean-post cosmetics from `Params.Sim3d`. lil-gui holds the read-only info
    // HUD and client-side camera controls.
    updateRadarFootprintInfo();
    const infoFolder = gui.addFolder("Info (Boden-Footprint)");
    infoFolder
      .add(radarFootprintInfo, "footprintDiameterM")
      .name("Ø (m)")
      .listen()
      .disable();
    infoFolder
      .add(radarFootprintInfo, "reachM")
      .name("Reichweite (m)")
      .listen()
      .disable();
    infoFolder
      .add(radarFootprintInfo, "sensorHeightM")
      .name("Sensor-Höhe (m)")
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
    destroySceneLabels();
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

    // Thin ring marking the sensor mounting circle (radial distance from center).
    const sensorRadius =
      sensorPoses.length > 0 ? sensorPoses[0].distanceCm / 100 : 0;
    if (sensorRadius > 0) {
      const inner = document.createElement('a-ring');
      inner.setAttribute('position', '0 0.02 0');
      inner.setAttribute('rotation', '-90 0 0');
      inner.setAttribute('radius-inner', Math.max(0, sensorRadius - 0.01).toString());
      inner.setAttribute('radius-outer', (sensorRadius + 0.01).toString());
      inner.setAttribute(
        'material',
        'shader: flat; color: #222; opacity: 0.85; transparent: true; side: double'
      );
      g.appendChild(inner);
    }

    // Outer ring on the LED panel ring radius (optional radar debug overlay).
    if (renderRadarCones) {
      const outer = document.createElement('a-ring');
      outer.setAttribute('id', 'radar-outer-ring');
      outer.setAttribute('position', '0 0.015 0');
      outer.setAttribute('rotation', '-90 0 0');
      outer.setAttribute('radius-inner', (ringRadiusM - 0.04).toString());
      outer.setAttribute('radius-outer', (ringRadiusM + 0.04).toString());
      outer.setAttribute(
        'material',
        'shader: flat; color: #4488cc; opacity: 0.35; transparent: true; side: double'
      );
      g.appendChild(outer);
    }
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
    if (!renderRadarCones || sensorPoses.length === 0) return root;

    const T = getThree();
    const y = 0.03;
    const FOOTPRINT_COLOR = 0xffee00;

    for (const pose of sensorPoses) {
      const r = sensorGroundRadiusM(pose);
      if (r <= 0) continue;
      const { x, z } = sensorGroundPos(pose);

      const disc = document.createElement('a-ring');
      disc.setAttribute('position', `${x} ${y} ${z}`);
      disc.setAttribute('rotation', '-90 0 0');
      disc.setAttribute('radius-inner', '0');
      disc.setAttribute('radius-outer', r.toString());
      disc.setAttribute(
        'material',
        'shader: flat; color: #ffee00; opacity: 0.15; transparent: true; side: double'
      );
      root.appendChild(disc);

      // Bright outline slightly above the fill to avoid z-fighting.
      const steps = 96;
      const pts: any[] = [];
      for (let i = 0; i <= steps; i++) {
        const a = (i / steps) * Math.PI * 2;
        pts.push(new T.Vector3(x + r * Math.cos(a), y + 0.002, z + r * Math.sin(a)));
      }
      const lineGeo = new T.BufferGeometry().setFromPoints(pts);
      const lineMat = new T.LineBasicMaterial({ color: FOOTPRINT_COLOR });
      const host = document.createElement('a-entity');
      host.setObject3D('mesh', new T.LineLoop(lineGeo, lineMat));
      root.appendChild(host);
    }
    return root;
  }

  /**
   * Central mast + hub disk + slats to each sensor. Sensors stay at their real
   * installation poses; slats run from the disk edge up (~15° with Nation2026
   * geometry) to the underside of each radar chip.
   */
  createRadarMastAssembly() {
    const root = document.createElement('a-entity');
    root.setAttribute('id', 'radar-mast');

    const mast = document.createElement('a-cylinder');
    mast.setAttribute('radius', RADAR_MAST_RADIUS_M.toString());
    mast.setAttribute('height', RADAR_MAST_HEIGHT_M.toString());
    mast.setAttribute('color', RADAR_WOOD_COLOR);
    mast.setAttribute('roughness', '0.72');
    mast.setAttribute('position', `0 ${RADAR_MAST_HEIGHT_M / 2} 0`);
    root.appendChild(mast);

    const disk = document.createElement('a-cylinder');
    disk.setAttribute('radius', RADAR_DISK_RADIUS_M.toString());
    disk.setAttribute('height', RADAR_DISK_THICKNESS_M.toString());
    disk.setAttribute('color', RADAR_DISK_COLOR);
    disk.setAttribute('roughness', '0.68');
    disk.setAttribute(
      'position',
      `0 ${RADAR_MAST_HEIGHT_M + RADAR_DISK_THICKNESS_M / 2} 0`,
    );
    root.appendChild(disk);

    const diskTopY = RADAR_MAST_HEIGHT_M + RADAR_DISK_THICKNESS_M;

    for (const pose of sensorPoses) {
      const { x, z } = sensorGroundPos(pose);
      const dist = Math.hypot(x, z);
      if (dist < 0.001) continue;

      const height = pose.heightCm / 100;
      const chipBottomY = height - RADAR_CHIP_H_M;
      const ux = x / dist;
      const uz = z / dist;
      const innerX = ux * RADAR_DISK_RADIUS_M;
      const innerZ = uz * RADAR_DISK_RADIUS_M;

      root.appendChild(
        createWoodSlat(
          innerX,
          diskTopY,
          innerZ,
          x,
          chipBottomY,
          z,
          RADAR_SLAT_RADIUS_M,
          RADAR_WOOD_COLOR,
        ),
      );
    }

    return root;
  }

  /**
   * One sensor per installation radar pose. Each sensor sits at its real global
   * mount position (X/Z from angle + distance, Y = mounting height) on a slat
   * from the central mast disk, and always looks straight down: green chip plus
   * a coverage cone (120° full angle) pointing −Y.
   */
  createRadarSensors() {
    clearSceneLabels('sensor');
    const root = document.createElement('a-entity');
    root.setAttribute('id', 'radar-sensors');

    root.appendChild(this.createRadarMastAssembly());

    for (let i = 0; i < sensorPoses.length; i++) {
      const pose = sensorPoses[i]!;
      const { x, z } = sensorGroundPos(pose);
      const height = pose.heightCm / 100;
      const deviceId = pose.deviceId || i + 1;

      // Green chip at the sensor, antenna facing down.
      const chip = document.createElement('a-box');
      chip.setAttribute('width', RADAR_CHIP_W_M.toString());
      chip.setAttribute('height', RADAR_CHIP_H_M.toString());
      chip.setAttribute('depth', RADAR_CHIP_D_M.toString());
      chip.setAttribute('color', RADAR_CHIP_COLOR);
      chip.setAttribute('roughness', '0.4');
      chip.setAttribute('position', `${x} ${height - RADAR_CHIP_H_M / 2} ${z}`);
      root.appendChild(chip);

      if (renderRadarCones) {
        // Cone apex at the chip underside, opening straight down (−Y). Yaw only
        // (angle + rotation) orients the spherical cap / local +X like radar_live.
        const half = (RADAR_SPOT_HALF_ANGLE_DEG * Math.PI) / 180;
        const slant = height / Math.cos(half);
        const yawDeg = pose.angleDeg + pose.rotationDeg;
        const coneHost = document.createElement('a-entity');
        coneHost.setAttribute(
          'position',
          `${x} ${height - RADAR_CHIP_H_M} ${z}`
        );
        coneHost.setAttribute('rotation', `0 ${yawDeg} 0`);
        coneHost.setAttribute(
          'radar-cone-viz',
          `length: ${slant}; halfAngleDeg: ${RADAR_SPOT_HALF_ANGLE_DEG}`
        );
        root.appendChild(coneHost);
      }

      const radial = Math.hypot(x, z) || 1;
      const labelX = x + (x / radial) * LABEL_OUTWARD_OFFSET_M;
      const labelZ = z + (z / radial) * LABEL_OUTWARD_OFFSET_M;
      addSceneLabel(
        'sensor',
        deviceLetter(deviceId),
        labelX,
        height + 0.28,
        labelZ,
        sensorColor(deviceId),
      );
    }
    if (labelsHookRoot) refreshSceneLabelsDom(labelsHookRoot);
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
    // Equirectangular pano: 90° clockwise (viewed from inside) → −Y
    skyEl.setAttribute('rotation', '0 -90 0');
    return skyEl;
  }

  createPanels() {
    clearSceneLabels('panel');
    panels.length = 0;
    textures.length = 0;
    const panelsEl = document.createElement('a-entity') as any;
    panelsEl.setAttribute('id', 'panels');
    for (let i = 0; i < numPanels; i++) {
      const slot = panelSlotForIndex(i);
      const group = document.createElement('a-entity') as any;
      group.object3D.position.set(slot.xM, 0, slot.zM);
      group.object3D.rotation.y = slot.rotationY;
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
      front.setAttribute('geometry', `primitive: plane; height: ${panelWidthM}; width: ${panelWidthM}`);
      front.setAttribute('material', 'shader: led-shader; transparent: true');
      front.setAttribute('led-panel', `textureIndex: ${i}; side: front`);
      front.setAttribute('position', `0 ${poleHeight + panelWidthM/2} ${panelDepthM/2 + 0.1}`);
      // Back plane
      const back = document.createElement('a-entity');
      back.setAttribute('geometry', `primitive: plane; height: ${panelWidthM}; width: ${panelWidthM}`);
      back.setAttribute('material', 'shader: led-shader; transparent: true');
      back.setAttribute('led-panel', `textureIndex: ${i}; side: back`);
      back.setAttribute('rotation', `0 180 0`);
      back.setAttribute('position', `0 ${poleHeight + panelWidthM/2} ${-(panelDepthM/2 + 0.1)}`);
      // Center box (optional, as the panel "body")
      const center = document.createElement('a-entity');
      center.setAttribute('geometry', `primitive: box; height: ${panelWidthM}; width: ${panelWidthM}; depth: ${panelDepthM}`);
      center.setAttribute('material', 'color: #fff; roughness: 0.4');
      center.setAttribute('position', `0 ${poleHeight + panelWidthM/2} 0`);
      // Poles
      const poleLeft = document.createElement('a-cylinder');
      poleLeft.setAttribute('radius', (poleDiameter / 2).toString());
      poleLeft.setAttribute('height', poleHeight.toString());
      poleLeft.setAttribute('color', '#8B4513');
      poleLeft.setAttribute('position', `${-panelWidthM/2 + poleDiameter/2} ${poleHeight/2} 0`);
      const poleRight = document.createElement('a-cylinder');
      poleRight.setAttribute('radius', (poleDiameter / 2).toString());
      poleRight.setAttribute('height', poleHeight.toString());
      poleRight.setAttribute('color', '#8B4513');
      poleRight.setAttribute('position', `${panelWidthM/2 - poleDiameter/2} ${poleHeight/2} 0`);
      group.appendChild(center);
      group.appendChild(front);
      group.appendChild(back);
      group.appendChild(poleLeft);
      group.appendChild(poleRight);
      panelsEl.appendChild(group);

      const ringDist = Math.hypot(slot.xM, slot.zM) || 1;
      const outwardX = slot.xM / ringDist;
      const outwardZ = slot.zM / ringDist;
      const labelY = poleHeight + panelWidthM + 0.35;
      const labelOutward = panelDepthM / 2 + 0.45;
      addSceneLabel(
        'panel',
        String(slot.panelNumber),
        slot.xM + outwardX * labelOutward,
        labelY,
        slot.zM + outwardZ * labelOutward,
        PANEL_LABEL_COLOR,
      );
    }
    panelsEl.setAttribute('update-panel-textures', '');
    if (labelsHookRoot) refreshSceneLabelsDom(labelsHookRoot);
    return panelsEl;
  }

  handleParams(param: Param["param"]) {
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
      renderRadarCones = Boolean(param.render_radar_cones);
      this.updateRadarVisualization();
    }
  }

  /**
   * Apply the authoritative installation geometry (ring, panel dimensions,
   * north panel, platform, real radar sensor poses) and rebuild the affected
   * parts of the scene.
   */
  applyInstallationState(payload: InstallationPayload) {
    if (payload.ring_radius_m != null) ringRadiusM = Number(payload.ring_radius_m);
    if (payload.num_panels != null) numPanels = Number(payload.num_panels);
    if (payload.north_panel != null) northPanel = Number(payload.north_panel);
    if (payload.platform_radius_m != null) {
      platformRadiusM = Number(payload.platform_radius_m);
    }
    if (payload.panel_width_m != null) panelWidthM = Number(payload.panel_width_m);
    if (payload.panel_depth_m != null) panelDepthM = Number(payload.panel_depth_m);

    if (Array.isArray(payload.panels)) {
      panelSlots = payload.panels.map((p) => {
        const { x, z } = radarGlobalToAframeXZ(Number(p.x_m), Number(p.z_m));
        return {
          index: Number(p.index),
          panelNumber: Number(p.panel_number),
          xM: x,
          zM: z,
          rotationY: Math.atan2(x, z) + Math.PI,
        };
      });
    } else {
      panelSlots = [];
    }

    if (Array.isArray(payload.sensors)) {
      sensorPoses = payload.sensors.map((s, i) => ({
        deviceId: Number(s.device_id ?? i + 1),
        angleDeg: Number(s.angle_deg),
        rotationDeg: Number(s.rotation_deg ?? 0),
        distanceCm: Number(s.distance_cm),
        rangeCm: Number(s.range_cm),
        heightCm: Number(s.height_cm),
        xM: Number(s.x_m),
        zM: Number(s.z_m),
      }));
    }
  }

  handleInstallation(payload: InstallationPayload) {
    this.applyInstallationState(payload);
    this.updatePanels();
    this.updateCentralCylinder();
    this.updateRadarVisualization();
  }

  registerComponents() {
    registerHumanComponents();
    if (!AFRAME.components['html-labels-sync']) {
      AFRAME.registerComponent('html-labels-sync', {
        tick() {
          syncSceneLabelsDom();
        },
      });
    }
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
      schema: {},
      vertexShader: vertexShader,
      fragmentShader: fragmentShader
    })
    AFRAME.registerShader('sky-shader', {
      schema: {},
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
    const oldRings = document.querySelector('#radar-ground-rings');
    const oldRadar = document.querySelector('#radar-sensors');
    const oldFootprints = document.querySelector('#radar-ground-footprints');
    oldRings?.parentNode?.removeChild(oldRings);
    oldRadar?.parentNode?.removeChild(oldRadar);
    oldFootprints?.parentNode?.removeChild(oldFootprints);
    sceneEl.appendChild(this.createRadarGroundRings());
    sceneEl.appendChild(this.createRadarSensors());
    sceneEl.appendChild(this.createRadarGroundFootprints());
    updateRadarFootprintInfo();
  }
}

export default makeHook(Pixels3dAframeHook);
