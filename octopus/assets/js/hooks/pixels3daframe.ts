import { Hook, makeHook } from "phoenix_typed_hook";
import AFRAME from "aframe";
// `aframe-orbit-controls` greift auf die Globals `AFRAME` und `THREE` zu, die
// A-Frame beim Laden auf `window` setzt — Import-Reihenfolge muss daher AFRAME
// → orbit-controls bleiben.
import "aframe-orbit-controls";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";
import { Frame, RGB, rgbPixelsFromFrame } from "./shared/frame";
import { getHumanWorld, registerHumanComponents } from "./humanComponents";
import type { HumanMode, HumanSource, RadarTrack } from "./humanWorld";

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

let panelDiameter = 18;
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

/** Radar-Sensoren: Abstand zum Zentrum (m) per lil-gui; Kegel-Visualisierung; Höhe per radarHeight */
let radarHeight = 3.5;
const RADAR_RADIUS_MIN_M = 0;
const RADAR_RADIUS_MAX_M = 8;
/** Horizontaler Abstand der Boxen von der Y-Achse (Kreisradius), Default 1.5 m */
let radarRadiusM = 1.5;
const RADAR_BOX = 0.1;
/** Neigung der Box/Kegel/Spot um lokale X-Achse (nach unten zur Mitte), ein Wert für alle Sensoren */
let radarTiltDeg = 45;
/** Toggle: semi-transparent blue cone meshes (`radar-cone-viz`) on each sensor */
let renderRadarCones = true;
/**
 * Voller Öffnungswinkel des Radar-Spotlights (A-Frame `light.angle`, Grad).
 * Der blaue Kegel (`radar-cone-viz`) nutzt denselben Winkel — Halbwinkel = /2.
 */
const RADAR_SPOT_ANGLE_DEG = 120;
const RADAR_SPOT_HALF_ANGLE_DEG = RADAR_SPOT_ANGLE_DEG / 2;
/** Three.js SpotLight: Intensität fällt auf 0 bei dieser Entfernung (m) */
const RADAR_SPOT_DISTANCE_M = 8;
/**
 * Anzahl Sensoren: muss gerade sein, weil sie paarweise an den Enden je eines
 * Dachbalkens hängen (2 Balken → 4 Sensoren, … 6 Balken → 12 Sensoren).
 */
const RADAR_COUNT_MIN = 4;
const RADAR_COUNT_MAX = 12;
const RADAR_COUNT_STEP = 2;
let radarCount = 6;
/** Zentraler Mast (unter den Radarboxen): Durchmesser per GUI 5–50 cm, Default 15 cm */
let mastDiameterM = 0.15;
const MAST_DIAMETER_MIN_M = 0.05;
const MAST_DIAMETER_MAX_M = 0.5;
/** Dachbalken-Stern statt Platte: Querschnitt (m) und kleine zentrale Nabe gegen Beam-Crossings. */
const BEAM_HEIGHT_M = 0.06;
const BEAM_WIDTH_M = 0.1;

/** Anlehn-Kegelstumpf auf der Plattform um den Mast: unten breit, oben schmal. Per GUI editierbar. */
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

/** Wenn true: Neigung so, dass die Oberkante der LED-Front (Panel 0) auf dem Kegelmantel liegt; Neigung-Slider gesperrt. */
let radarTiltAutoAlign = false;

let radarLilGui: GUI | null = null;
/** lil-gui Controller für „Neigung (°)“ — zum Sperren bei Auto-Ausrichtung */
let radarNeigungCtrl: { disable: (v: boolean) => void } | null = null;

/**
 * Orbit-Cam: Kamera kreist per Maus um `cameraTarget` (Linksklick = Rotate,
 * Rechtsklick = Pan, Mausrad = Zoom). Werte hier sind Defaults; lil-gui
 * (Kamera-Folder) schreibt direkt in diese Variablen und ruft
 * `applyCameraAttributes()` auf.
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

/** Humans-Mock: lokaler Avatar-Controller in `humanComponents.ts`/`humanWorld.ts`. */
let humanCount = 5;
let humanSpeed = 1.0;
let humanPaused = false;
let humanMode: HumanMode = "wander";
/** Datenquelle der Humans: lokales Mock-Modell oder echte Radar-Tracks vom Backend. */
let humanSource: HumanSource = "mock";

/** Sync `humans-root` schema attributes with the module-level state. */
function applyHumansAttributes() {
  const root = document.querySelector("#humans-root") as any;
  if (!root) return;
  root.setAttribute("humans-root", {
    count: humanCount,
    speed: humanSpeed,
    paused: humanPaused,
    mode: humanMode,
    panelDiameter,
    source: humanSource,
  });
}

/**
 * Footprint des sphärisch gekappten Radar-Kegels auf der Bodenebene (y = 0).
 *
 * Der `radar-cone-viz`-Kegel hat Apex am Sensor, Halbwinkel θ und Slant-Länge L
 * (= sphärische Kappe statt flacher Boden). Bei tilt > 0 ist der Schnitt mit
 * der Bodenebene eine Konik (Ellipse/Parabel), zusätzlich durch die Kappe
 * begrenzt. Wir samplen die Mantel- und Kappenrand-Kurve numerisch und
 * berechnen daraus die längste Sehne (Ø max) sowie die Querausdehnung
 * senkrecht dazu (Ø min).
 *
 * Annahme: yaw = 0 (alle Sensoren sind identisch parametriert, nur in Yaw
 * rotiert — der Footprint ist invariant unter Yaw-Rotation der Apex-Lage).
 */
type RadarFootprint = {
  hasGroundHit: boolean;
  maxDiameterM: number;
  minDiameterM: number;
  groundReachMaxM: number;
  groundReachMinM: number;
};

function computeRadarConeGroundFootprint(): RadarFootprint {
  const empty: RadarFootprint = {
    hasGroundHit: false,
    maxDiameterM: 0,
    minDiameterM: 0,
    groundReachMaxM: 0,
    groundReachMinM: 0,
  };
  const h = radarHeight;
  const r0 = radarRadiusM;
  if (h <= 0) return empty;

  const tiltRad = (radarTiltDeg * Math.PI) / 180;
  const theta = (RADAR_SPOT_HALF_ANGLE_DEG * Math.PI) / 180;
  const L = RADAR_SPOT_DISTANCE_M;
  const cosT = Math.cos(tiltRad);
  const sinT = Math.sin(tiltRad);
  const cosTh = Math.cos(theta);
  const sinTh = Math.sin(theta);

  // Apex S = (0, h, r0), Achse d = (0, -cos T, sin T),
  // Hilfsbasis e1 = (1,0,0), e2 = (0, sin T, cos T).
  // Strahlrichtung r̂(α, φ) = cos α · d + sin α · (cos φ · e1 + sin φ · e2).
  const points: Array<[number, number]> = [];

  // (1) Mantel (α = θ): φ über vollen Kreis sampeln, jeden mit Boden schneiden.
  const phiSteps = 360;
  for (let i = 0; i < phiSteps; i++) {
    const phi = (i / phiSteps) * 2 * Math.PI;
    const cphi = Math.cos(phi);
    const sphi = Math.sin(phi);
    const ry = -cosTh * cosT + sinTh * sphi * sinT;
    if (ry >= -1e-9) continue; // Strahl zeigt nicht nach unten → kein Bodenhit
    const t = -h / ry;
    if (t > L) continue; // verlässt Kegel via Kappe vor dem Boden
    const rx = sinTh * cphi;
    const rz = cosTh * sinT + sinTh * sphi * cosT;
    points.push([t * rx, r0 + t * rz]);
  }

  // (2) Kappenrand schneidet Boden: |P-S| = L, α ∈ (0, θ]. Aus P_y = 0 folgt
  // sin φ = (cos α · cos T − h/L) / (sin α · sin T) (sofern Nenner ≠ 0).
  const alphaSteps = 90;
  for (let j = 1; j <= alphaSteps; j++) {
    const alpha = (j / alphaSteps) * theta;
    const cA = Math.cos(alpha);
    const sA = Math.sin(alpha);
    const denom = sA * sinT;
    if (Math.abs(denom) < 1e-9) continue;
    const sinPhi = (cA * cosT - h / L) / denom;
    if (sinPhi > 1 + 1e-9 || sinPhi < -1 - 1e-9) continue;
    const sp = Math.max(-1, Math.min(1, sinPhi));
    const phi1 = Math.asin(sp);
    const phi2 = Math.PI - phi1;
    for (const phi of [phi1, phi2]) {
      const cphi = Math.cos(phi);
      const sphi = Math.sin(phi);
      const rx = sA * cphi;
      const rz = cA * sinT + sA * sphi * cosT;
      points.push([L * rx, r0 + L * rz]);
    }
  }

  if (points.length < 2) return empty;

  // Ø max: längste paarweise Distanz (O(N²), N ≈ 540 → ok, läuft nur on-change).
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

  // Ø min: Spannweite senkrecht zur Major-Achse.
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

  // Reichweite vom Sensorfußpunkt (0, r0) auf dem Boden.
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
};

function updateRadarFootprintInfo() {
  const fp = computeRadarConeGroundFootprint();
  const round3 = (v: number) => Math.round(v * 1000) / 1000;
  radarFootprintInfo.footprintMaxM = round3(fp.maxDiameterM);
  radarFootprintInfo.footprintMinM = round3(fp.minDiameterM);
  radarFootprintInfo.reachMaxM = round3(fp.groundReachMaxM);
  radarFootprintInfo.reachMinM = round3(fp.groundReachMinM);
}

/** Kegelachse (vom Sensor in den Kegel) wie in `createRadarSensors`: R_y(yaw) · R_x(-tilt) · (0,-1,0). */
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

/**
 * Neigung (°), sodass die Oberkante der Front-Plane (Panel azimuth 0) auf dem Kegelmantel liegt
 * (Halbwinkel = RADAR_SPOT_HALF_ANGLE_DEG) und knapp darüber außerhalb des Kegels.
 */
function computeAutoRadarTiltDeg(): number {
  const T = getThree();
  const yTop = poleHeight + PANEL_SIZE;
  const zFace = PANEL_DEPTH / 2 + 0.1;
  const TzWorld = panelDiameter / 2 - zFace;
  const S = new T.Vector3(0, radarHeight, radarRadiusM);
  const Top = new T.Vector3(0, yTop, TzWorld);
  const w = new T.Vector3().subVectors(Top, S);
  const wLen = w.length();
  if (wLen < 1e-6) return T.MathUtils.clamp(radarTiltDeg, 5, 85);
  w.multiplyScalar(1 / wLen);

  // Auto-Neigung soll auf die Kegelachse (gelbe Linie) zielen: Achse || w.
  // Für yaw=0 bleibt alles in der YZ-Ebene. Achse nach Tilt t ist (0, -cos t, sin t).
  // => tan(t) = w.z / (-w.y)
  const tRad = Math.atan2(w.z, -w.y);
  const tDeg = T.MathUtils.radToDeg(tRad);
  return T.MathUtils.clamp(tDeg, 5, 85);
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
        // Im Mock-Modus ignorieren — wir wollen das Modell nicht durcheinanderbringen.
        if (humanSource !== "radar") return;
        const world = getHumanWorld();
        if (!world) return;
        world.setRadarTracks(Array.isArray(payload?.tracks) ? payload.tracks : []);
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

    const humansRoot = this.createHumansRoot();
    sceneEl.appendChild(humansRoot);

    const cameraRig = this.createCameraRig();
    sceneEl.appendChild(cameraRig);

    this.el.appendChild(sceneEl);
    this.setupRadarGui();
  }

  setupRadarGui() {
    radarLilGui?.destroy();
    radarNeigungCtrl = null;
    if (radarTiltAutoAlign) {
      radarTiltDeg = computeAutoRadarTiltDeg();
    }
    const params = {
      panelDiameter,
      radarHeight,
      radarTiltDeg,
      radarCount,
      radarRadiusM,
      mastDiameterM,
      renderRadarCones,
      radarTiltAutoAlign,
    };
    const gui = new GUI({ title: "Sim 3D" });
    radarLilGui = gui;
    const panelsFolder = gui.addFolder("Panels");
    panelsFolder
      .add(params, "panelDiameter", PANEL_DIAMETER_MIN, PANEL_DIAMETER_MAX, 0.1)
      .name("Durchmesser")
      .onChange((v: number) => {
        panelDiameter = clampPanelDiameter(v);
        params.panelDiameter = panelDiameter;
        this.updatePanels();
        this.updateRadarVisualization();
        applyHumansAttributes();
      });
    panelsFolder.open();
    const folder = gui.addFolder("Radar");
    const radarRadiusMinM = Math.max(RADAR_RADIUS_MIN_M, mastDiameterM / 2);
    folder
      .add(params, "radarTiltAutoAlign")
      .name("Neigung: Auto (Mitte = Kante)")
      .onChange((v: boolean) => {
        radarTiltAutoAlign = !!v;
        params.radarTiltAutoAlign = radarTiltAutoAlign;
        if (radarTiltAutoAlign) {
          radarTiltDeg = computeAutoRadarTiltDeg();
          params.radarTiltDeg = radarTiltDeg;
        }
        this.updateRadarVisualization();
        radarNeigungCtrl?.disable(!!radarTiltAutoAlign);
        const nc = radarNeigungCtrl as { object?: { radarTiltDeg?: number }; updateDisplay?: () => void } | null;
        if (nc?.object) nc.object.radarTiltDeg = radarTiltDeg;
        nc?.updateDisplay?.();
      });
    folder
      .add(params, "renderRadarCones")
      .name("Blaue Licht-Kegel")
      .onChange((v: boolean) => {
        renderRadarCones = !!v;
        params.renderRadarCones = renderRadarCones;
        this.updateRadarVisualization();
      });
    folder
      .add(params, "radarCount", RADAR_COUNT_MIN, RADAR_COUNT_MAX, RADAR_COUNT_STEP)
      .name("Anzahl Sensoren (= 2·Balken)")
      .onChange((v: number) => {
        radarCount = clampRadarCount(v);
        params.radarCount = radarCount;
        this.updateRadarVisualization();
      });
    folder
      .add(params, "radarRadiusM", radarRadiusMinM, RADAR_RADIUS_MAX_M, 0.01)
      .name("Abstand zum Zentrum (m)")
      .onChange((v: number) => {
        radarRadiusM = Math.min(
          RADAR_RADIUS_MAX_M,
          Math.max(radarRadiusMinM, Number(v))
        );
        params.radarRadiusM = radarRadiusM;
        this.updateRadarVisualization();
      });
    folder
      .add(params, "radarHeight", 0.5, 12, 0.05)
      .name("Gruppen-Höhe (m)")
      .onChange((v: number) => {
        radarHeight = v;
        params.radarHeight = radarHeight;
        this.updateRadarVisualization();
      });
    folder
      .add(params, "mastDiameterM", MAST_DIAMETER_MIN_M, MAST_DIAMETER_MAX_M, 0.005)
      .name("Mast-Durchmesser (m)")
      .onChange((v: number) => {
        mastDiameterM = Math.min(
          MAST_DIAMETER_MAX_M,
          Math.max(MAST_DIAMETER_MIN_M, Number(v))
        );
        params.mastDiameterM = mastDiameterM;
        this.applyRadarMastConstraints();
        this.updateRadarVisualization();
        this.setupRadarGui();
      });
    radarNeigungCtrl = folder
      .add(params, "radarTiltDeg", 0, 120, 1)
      .name("Neigung (°)")
      .onChange((v: number) => {
        if (radarTiltAutoAlign) return;
        radarTiltDeg = v;
        this.updateRadarVisualization();
      });
    if (radarTiltAutoAlign) {
      radarNeigungCtrl.disable(true);
    }
    folder.open();

    const leanParams = { leanPostBottomR, leanPostTopR, leanPostHeight };
    const leanFolder = gui.addFolder("Rückenlehne");
    leanFolder
      .add(leanParams, "leanPostBottomR", LEAN_POST_BOTTOM_R_MIN_M, LEAN_POST_BOTTOM_R_MAX_M, 0.01)
      .name("Radius unten (m)")
      .onChange((v: number) => {
        leanPostBottomR = Math.min(
          LEAN_POST_BOTTOM_R_MAX_M,
          Math.max(LEAN_POST_BOTTOM_R_MIN_M, Number(v))
        );
        leanParams.leanPostBottomR = leanPostBottomR;
        this.updateLeanPost();
      });
    leanFolder
      .add(leanParams, "leanPostTopR", LEAN_POST_TOP_R_MIN_M, LEAN_POST_TOP_R_MAX_M, 0.01)
      .name("Radius oben (m)")
      .onChange((v: number) => {
        leanPostTopR = Math.min(
          LEAN_POST_TOP_R_MAX_M,
          Math.max(LEAN_POST_TOP_R_MIN_M, Number(v))
        );
        leanParams.leanPostTopR = leanPostTopR;
        this.updateLeanPost();
      });
    leanFolder
      .add(leanParams, "leanPostHeight", LEAN_POST_HEIGHT_MIN_M, LEAN_POST_HEIGHT_MAX_M, 0.01)
      .name("Höhe (m)")
      .onChange((v: number) => {
        leanPostHeight = Math.min(
          LEAN_POST_HEIGHT_MAX_M,
          Math.max(LEAN_POST_HEIGHT_MIN_M, Number(v))
        );
        leanParams.leanPostHeight = leanPostHeight;
        this.updateLeanPost();
      });
    leanFolder.open();

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
    infoFolder.open();

    const humansParams = {
      humanSource,
      humanCount,
      humanSpeed,
      humanPaused,
      humanMode,
    };
    const humansFolder = gui.addFolder("Humans");
    humansFolder
      .add(humansParams, "humanSource", { Mock: "mock", "Radar (live)": "radar" })
      .name("Quelle")
      .onChange((v: string) => {
        humanSource = v === "radar" ? "radar" : "mock";
        humansParams.humanSource = humanSource;
        applyHumansAttributes();
      });
    humansFolder
      .add(humansParams, "humanCount", 0, 10, 1)
      .name("Anzahl (nur Mock)")
      .onChange((v: number) => {
        humanCount = Math.max(0, Math.round(Number(v)));
        humansParams.humanCount = humanCount;
        applyHumansAttributes();
      });
    humansFolder
      .add(humansParams, "humanSpeed", 0, 2, 0.05)
      .name("Geschwindigkeit (nur Mock)")
      .onChange((v: number) => {
        humanSpeed = Math.max(0, Number(v));
        humansParams.humanSpeed = humanSpeed;
        applyHumansAttributes();
      });
    humansFolder
      .add(humansParams, "humanPaused")
      .name("Pause (nur Mock)")
      .onChange((v: boolean) => {
        humanPaused = !!v;
        humansParams.humanPaused = humanPaused;
        applyHumansAttributes();
      });
    humansFolder
      .add(humansParams, "humanMode", ["wander", "approach"])
      .name("Modus (nur Mock)")
      .onChange((v: HumanMode) => {
        humanMode = v === "approach" ? "approach" : "wander";
        humansParams.humanMode = humanMode;
        applyHumansAttributes();
      });
    humansFolder.open();

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
   * Setzt die Kamera-Position auf den Default zurück. Reicht nicht, einfach
   * `setAttribute('position', …)` zu rufen — `orbit-controls` hält den
   * THREE-State intern. Wir entfernen das Component und setzen es neu, dann
   * greift `initialPosition` wieder.
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
    radarNeigungCtrl = null;
  }

  /**
   * Orbit-Cam: ein einzelnes Entity trägt sowohl `camera` als auch
   * `orbit-controls` (das Component verlangt `dependencies: ['camera']` und
   * greift auf `getObject3D('camera')` desselben Entitys zu — kein Rig).
   * `look-controls`/`wasd-controls` werden vom Component automatisch
   * deaktiviert, wenn vorhanden.
   */
  createCameraRig() {
    const cam = document.createElement("a-entity");
    cam.setAttribute("id", "cameraRig");
    cam.setAttribute("camera", `fov: ${cameraFov}; near: 0.05; far: 2000`);
    // Wichtig: Entity bleibt am Origin. `orbit-controls` schreibt die
    // gewünschte Eye-Position in `getObject3D('camera').position` (Local
    // gegenüber diesem Entity). Eine zusätzliche `position` auf dem Entity
    // würde die Eye-Position verschieben und Target verfälschen.
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
      spotlight.setAttribute('rotation', '-90 0 0'); // nach oben
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

    // Repeat-Wrapping für Texturen setzen, damit repeat funktioniert
    groundEl.addEventListener('materialtextureloaded', () => {
      const mesh = (groundEl as any).getObject3D('mesh');
      if (!mesh) return;
      ['map', 'normalMap', 'roughnessMap'].forEach((key) => {
        const tex = mesh.material[key];
        if (tex) {
          tex.wrapS = tex.wrapT = getThree().RepeatWrapping;
          tex.repeat.set(1000, 1000); // oder gewünschtes repeat
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
    const rInner = Math.max(0, radarRadiusM - 0.01);
    const rOuter = radarRadiusM + 0.01;
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
   * Kreis der Radarboxen: Radius mindestens Mast-Radius (Abstand ≥ Mast-Durchmesser/2).
   * @returns true wenn radarRadiusM angepasst wurde (GUI ggf. neu aufsetzen)
   */
  applyRadarMastConstraints(): boolean {
    const rMin = mastDiameterM / 2;
    const prev = radarRadiusM;
    radarRadiusM = Math.max(rMin, Math.min(RADAR_RADIUS_MAX_M, radarRadiusM));
    return Math.abs(prev - radarRadiusM) > 1e-9;
  }

  /**
   * Mast + Dachbalken-Stern (#8B4513): Unterkante Podest (0.5 m), Oberseite der Balken bündig
   * unter Radarbox-Unterkante. Anzahl Balken = `radarCount / 2`, jeder Balken verbindet zwei
   * gegenüberliegende Sensoren (Beam k bei Yaw `(k/n)·360°` hat lokale Z-Achse auf den
   * Sensoren k und k+n/2). Beam-Länge = `2·radarRadiusM + RADAR_BOX`, damit die Sensorboxen
   * bündig an den Balkenenden sitzen. Kleine zentrale Nabe verdeckt die Beam-Kreuzung.
   */
  createRadarMast() {
    const PEDESTAL_TOP_Y = 0.5;
    const boxBottomY = radarHeight - RADAR_BOX / 2;
    const totalSpan = Math.max(0, boxBottomY - PEDESTAL_TOP_Y);
    const holder = document.createElement("a-entity");
    holder.setAttribute("id", "radar-mast");
    if (totalSpan <= 1e-6) return holder;

    const beamH = Math.min(BEAM_HEIGHT_M, totalSpan);
    const mastBodyH = totalSpan - beamH;
    const beamY = PEDESTAL_TOP_Y + mastBodyH + beamH / 2;

    if (mastBodyH > 1e-6) {
      const cyl = document.createElement("a-cylinder");
      cyl.setAttribute("radius", (mastDiameterM / 2).toString());
      cyl.setAttribute("height", mastBodyH.toString());
      cyl.setAttribute("color", "#8B4513");
      cyl.setAttribute("roughness", "0.65");
      cyl.setAttribute(
        "position",
        `0 ${PEDESTAL_TOP_Y + mastBodyH / 2} 0`
      );
      holder.appendChild(cyl);
    }

    if (beamH > 1e-6) {
      const sensorCount = clampRadarCount(radarCount);
      const numBeams = sensorCount / 2;
      const beamLen = 2 * radarRadiusM + RADAR_BOX;
      const T = getThree();
      for (let k = 0; k < numBeams; k++) {
        const yawDeg = T.MathUtils.radToDeg((k / sensorCount) * Math.PI * 2);
        const beam = document.createElement("a-box");
        beam.setAttribute("width", BEAM_WIDTH_M.toString());
        beam.setAttribute("height", beamH.toString());
        beam.setAttribute("depth", beamLen.toString());
        beam.setAttribute("color", "#8B4513");
        beam.setAttribute("roughness", "0.65");
        beam.setAttribute("position", `0 ${beamY} 0`);
        beam.setAttribute("rotation", `0 ${yawDeg} 0`);
        holder.appendChild(beam);
      }
      const hubR = Math.max(mastDiameterM / 2, BEAM_WIDTH_M * 0.9);
      const hub = document.createElement("a-cylinder");
      hub.setAttribute("radius", hubR.toString());
      hub.setAttribute("height", beamH.toString());
      hub.setAttribute("color", "#7a3d11");
      hub.setAttribute("roughness", "0.7");
      hub.setAttribute("position", `0 ${beamY} 0`);
      holder.appendChild(hub);
    }
    return holder;
  }

  createRadarSensors() {
    const root = document.createElement('a-entity');
    root.setAttribute('id', 'radar-sensors');
    const n = clampRadarCount(radarCount);
    const T = getThree();
    for (let i = 0; i < n; i++) {
      const angle = (i / n) * Math.PI * 2;
      const x = radarRadiusM * Math.sin(angle);
      const z = radarRadiusM * Math.cos(angle);
      // +Z radial nach außen (ohne +180 — sonst zeigen Sensoren zur Mitte)
      const yawDeg = T.MathUtils.radToDeg(angle);
      const pivot = document.createElement('a-entity');
      pivot.setAttribute('position', `${x} ${radarHeight} ${z}`);
      pivot.setAttribute('rotation', `0 ${yawDeg} 0`);
      const tilt = document.createElement('a-entity');
      tilt.setAttribute('rotation', `${-radarTiltDeg} 0 0`);
      const box = document.createElement('a-box');
      box.setAttribute('width', RADAR_BOX.toString());
      box.setAttribute('height', RADAR_BOX.toString());
      box.setAttribute('depth', RADAR_BOX.toString());
      box.setAttribute('color', '#0a0a0a');
      box.setAttribute('position', '0 0 0');
      box.setAttribute('roughness', '0.6');
      if (renderRadarCones) {
        const coneHost = document.createElement('a-entity');
        coneHost.setAttribute('position', '0 0 0');
        coneHost.setAttribute(
          'radar-cone-viz',
          `length: ${RADAR_SPOT_DISTANCE_M}; halfAngleDeg: ${RADAR_SPOT_HALF_ANGLE_DEG}`
        );
        // Kegel unter gleicher tilt-Gruppe wie die Box: Spitze = Boxmitte, Öffnung in -Y = Neigungswinkel.
        // Kein a-light Spot: sonst würde das Radar andere Meshes (Mast, Boden) mitblau anstrahlen; der Effekt
        // kommt nur noch aus dem halbtransparenten Kegel-Mesh (radar-cone-viz), nicht aus Scene-Lighting.
        tilt.appendChild(coneHost);
      }
      tilt.appendChild(box);
      pivot.appendChild(tilt);
      root.appendChild(pivot);
    }
    return root;
  }

  createCentralCylinder() {
    const cyl = document.createElement('a-cylinder');
    cyl.setAttribute('id', 'central-platform');
    cyl.setAttribute('radius', '2.5');
    cyl.setAttribute('height', '0.5');
    cyl.setAttribute('position', '0 0.25 0');
    cyl.setAttribute('color', '#8B4513');
    return cyl;
  }

  /**
   * Anlehn-Kegelstumpf um den Mast: `a-cylinder` exponiert nur einen Radius,
   * deshalb `geometry: cone` mit `radiusBottom` ≠ `radiusTop`. Sitzt mittig
   * auf der Plattform (Top y=0.5), Mast wächst durch das hohle Innere weiter
   * nach oben.
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
    root.setAttribute('humans-root', {
      count: humanCount,
      speed: humanSpeed,
      paused: humanPaused,
      mode: humanMode,
      panelDiameter,
      source: humanSource,
    } as any);
    return root;
  }

  createLight() {
    // Directional Light wie 17 Uhr: warm, schräg von oben (Südwesten)
    const sun = document.createElement('a-entity');
    sun.setAttribute('light', 'type: directional; color: #ffd9a0; intensity: 1.1; castShadow: true');
    // Position: schräg von oben, Südwesten
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
      // 8x8 Textur
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
      // Front-Plane
      const front = document.createElement('a-entity');
      front.setAttribute('geometry', `primitive: plane; height: ${PANEL_SIZE}; width: ${PANEL_SIZE}`);
      front.setAttribute('material', 'shader: led-shader; transparent: true');
      front.setAttribute('led-panel', `textureIndex: ${i}; side: front`);
      front.setAttribute('position', `0 ${poleHeight + PANEL_SIZE/2} ${PANEL_DEPTH/2 + 0.1}`);
      // Back-Plane
      const back = document.createElement('a-entity');
      back.setAttribute('geometry', `primitive: plane; height: ${PANEL_SIZE}; width: ${PANEL_SIZE}`);
      back.setAttribute('material', 'shader: led-shader; transparent: true');
      back.setAttribute('led-panel', `textureIndex: ${i}; side: back`);
      back.setAttribute('rotation', `0 180 0`);
      back.setAttribute('position', `0 ${poleHeight + PANEL_SIZE/2} ${-(PANEL_DEPTH/2 + 0.1)}`);
      // Center-Box (optional, als "Körper" des Panels)
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
      this.setupRadarGui();
      applyHumansAttributes();
    }
    if (param.height) {
      poleHeight = param.height;
      this.updatePanels();
      if (radarTiltAutoAlign) {
        this.updateRadarVisualization();
      }
    }
    if (param.foot_diameter) {
      poleDiameter  = param.foot_diameter;
      this.updatePanels()
    }
    if (param.button_diameter) {
      buttonPolesRadius  = param.button_diameter / 2;
      this.updatePanels()
    }
    if (param.radar_count !== undefined && param.radar_count !== null) {
      radarCount = clampRadarCount(Number(param.radar_count));
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
        // `length` ist jetzt der Radius (Slant-Länge) vom Sensor: alle Punkte des Kegels
        // liegen ≤ length vom Apex. Statt flacher Basis schließt eine Sphärenkappe
        // (Kugel um Apex, Radius = length) den Kegel ab → kein gerades Abschneiden.
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
        // Spitze (Sensor) am Entity-Ursprung = Mitte der Box; Achse entlang -Y = gleiche Achse
        // wie die 45°-Tilt-Gruppe (kein extra X-Flip — sonst zeigt der Kegel nicht „mit“ der Box).
        const group = new T.Group();
        const coneMesh = new T.Mesh(coneGeo, mat);
        coneMesh.position.y = -h / 2;
        group.add(coneMesh);
        // Sphäre ist um Apex zentriert; 180°-Rotation um X dreht den Pol auf -Y, Rim landet
        // dadurch automatisch bei y=-h, Radius=r (= Kegel-Rim).
        const capMesh = new T.Mesh(capGeo, mat);
        capMesh.rotation.x = Math.PI;
        group.add(capMesh);
        this.el.setObject3D('mesh', group);

        // Zentrumslinie Kegel: von Spitze (0) bis zum Pol der Kappe (-L), ~2 cm Ø, neon-gelb
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
    if (radarTiltAutoAlign) {
      radarTiltDeg = computeAutoRadarTiltDeg();
    }
    if (this.applyRadarMastConstraints()) {
      this.setupRadarGui();
    }
    const oldRings = document.querySelector('#radar-ground-rings');
    const oldRadar = document.querySelector('#radar-sensors');
    const oldMast = document.querySelector('#radar-mast');
    oldRings?.parentNode?.removeChild(oldRings);
    oldRadar?.parentNode?.removeChild(oldRadar);
    oldMast?.parentNode?.removeChild(oldMast);
    sceneEl.appendChild(this.createRadarGroundRings());
    sceneEl.appendChild(this.createRadarMast());
    sceneEl.appendChild(this.createRadarSensors());
    if (radarTiltAutoAlign && radarNeigungCtrl) {
      const nc = radarNeigungCtrl as {
        object?: { radarTiltDeg?: number };
        updateDisplay?: () => void;
      };
      if (nc.object) nc.object.radarTiltDeg = radarTiltDeg;
      nc.updateDisplay?.();
    }
    updateRadarFootprintInfo();
  }
}

export default makeHook(Pixels3dAframeHook);
