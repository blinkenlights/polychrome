import { Hook, makeHook } from "phoenix_typed_hook";
import AFRAME from "aframe";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";
import { Frame, RGB, rgbPixelsFromFrame } from "./shared/frame";

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

let panelDiameter = 16;
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

/** Radar-Sensoren: kleiner Innenkreis (~30 cm Ø), Kegel-Visualisierung; Höhe per lil-gui / radarHeight */
let radarHeight = 3.5;
const RADAR_RING_RADIUS = 0.15;
const RADAR_BOX = 0.1;
/** Neigung der Box/Kegel/Spot um lokale X-Achse (nach unten zur Mitte), ein Wert für alle Sensoren */
let radarTiltDeg = 45;
/** Toggle: render radar boxes + blue lights at all */
let renderRadar = true;
/**
 * Voller Öffnungswinkel des Radar-Spotlights (A-Frame `light.angle`, Grad).
 * Der blaue Kegel (`radar-cone-viz`) nutzt denselben Winkel — Halbwinkel = /2.
 */
const RADAR_SPOT_ANGLE_DEG = 120;
const RADAR_SPOT_HALF_ANGLE_DEG = RADAR_SPOT_ANGLE_DEG / 2;
const RADAR_COUNT_MIN = 1;
const RADAR_COUNT_MAX = 12;
let radarCount = 6;

function clampRadarCount(v: number): number {
  return Math.min(RADAR_COUNT_MAX, Math.max(RADAR_COUNT_MIN, Math.round(Number(v))));
}

let radarLilGui: GUI | null = null;

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

    const radarGround = this.createRadarGroundRings();
    if (renderRadar) {
      sceneEl.appendChild(radarGround);
    }

    const radarSensors = this.createRadarSensors();
    if (renderRadar) {
      sceneEl.appendChild(radarSensors);
    }

    const cameraRig = this.createCameraRig();
    sceneEl.appendChild(cameraRig);

    this.el.appendChild(sceneEl);
    this.setupRadarGui();
  }

  setupRadarGui() {
    radarLilGui?.destroy();
    const params = { radarHeight, radarTiltDeg, radarCount, renderRadar };
    const gui = new GUI({ title: "Sim 3D" });
    radarLilGui = gui;
    const folder = gui.addFolder("Radar");
    folder
      .add(params, "renderRadar")
      .name("Rendern")
      .onChange((v: boolean) => {
        renderRadar = !!v;
        params.renderRadar = renderRadar;
        this.updateRadarVisualization();
      });
    folder
      .add(params, "radarCount", RADAR_COUNT_MIN, RADAR_COUNT_MAX, 1)
      .name("Anzahl Boxen")
      .onChange((v: number) => {
        radarCount = clampRadarCount(v);
        params.radarCount = radarCount;
        this.updateRadarVisualization();
      });
    folder
      .add(params, "radarHeight", 0.5, 12, 0.05)
      .name("Gruppen-Höhe (m)")
      .onChange((v: number) => {
        radarHeight = v;
        this.updateRadarVisualization();
      });
    folder
      .add(params, "radarTiltDeg", 5, 85, 1)
      .name("Neigung (°)")
      .onChange((v: number) => {
        radarTiltDeg = v;
        this.updateRadarVisualization();
      });
    folder.open();
  }

  destroyed() {
    radarLilGui?.destroy();
    radarLilGui = null;
  }

  createCameraRig() {
    const cameraRig = document.createElement('a-entity');
    cameraRig.setAttribute('id', 'cameraRig');
    const camera = document.createElement('a-entity');
    camera.setAttribute('camera', '');
    camera.setAttribute('position', '0 1.6 0');
    camera.setAttribute('look-controls', '');
    cameraRig.appendChild(camera);
    return cameraRig;
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
    inner.setAttribute('radius-inner', '0.14');
    inner.setAttribute('radius-outer', '0.16');
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

  createRadarSensors() {
    const root = document.createElement('a-entity');
    root.setAttribute('id', 'radar-sensors');
    const n = clampRadarCount(radarCount);
    const outerR = panelDiameter / 2;
    const radialSpan = Math.max(0.01, outerR - RADAR_RING_RADIUS);
    const beamLen = Math.sqrt(radialSpan * radialSpan + radarHeight * radarHeight);
    const T = getThree();
    for (let i = 0; i < n; i++) {
      const angle = (i / n) * Math.PI * 2;
      const x = RADAR_RING_RADIUS * Math.sin(angle);
      const z = RADAR_RING_RADIUS * Math.cos(angle);
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
      const coneHost = document.createElement('a-entity');
      coneHost.setAttribute('position', '0 0 0');
      coneHost.setAttribute(
        'radar-cone-viz',
        `length: ${beamLen}; halfAngleDeg: ${RADAR_SPOT_HALF_ANGLE_DEG}`
      );
      // Kegel unter gleicher tilt-Gruppe wie die Box: Spitze = Boxmitte, Öffnung in -Y = Neigungswinkel
      tilt.appendChild(coneHost);
      tilt.appendChild(box);
      // Spot entlang lokalem -Y (Kegelachse): Default -Z → Rx(-90) → -Y
      const spot = document.createElement('a-light');
      spot.setAttribute('type', 'spot');
      spot.setAttribute('color', '#9ec8ff');
      spot.setAttribute('intensity', '0.45');
      spot.setAttribute('angle', String(RADAR_SPOT_ANGLE_DEG));
      spot.setAttribute('distance', String(beamLen * 1.25));
      spot.setAttribute('decay', '1.5');
      spot.setAttribute('cast-shadow', 'false');
      spot.setAttribute('rotation', '-90 0 0');
      tilt.appendChild(spot);
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
    if (param.diameter) {
      panelDiameter = param.diameter;
      this.updatePanels();
      this.updateRadarVisualization();
    }
    if (param.height) {
      poleHeight  = param.height;
      this.updatePanels()
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
        const h = this.data.length;
        const r = Math.tan(T.MathUtils.degToRad(this.data.halfAngleDeg)) * h;
        const geo = new T.CylinderGeometry(0, r, h, 32, 1, false);
        const mat = new T.MeshBasicMaterial({
          color: 0x66aaff,
          transparent: true,
          opacity: 0.16,
          depthWrite: false,
          side: T.DoubleSide,
        });
        const mesh = new T.Mesh(geo, mat);
        // Spitze (Sensor) am Entity-Ursprung = Mitte der Box; Achse entlang -Y = gleiche Achse
        // wie die 45°-Tilt-Gruppe (kein extra X-Flip — sonst zeigt der Kegel nicht „mit“ der Box).
        mesh.position.y = -h / 2;
        this.el.setObject3D('mesh', mesh);
      },
      remove: function (this: { el: any }) {
        this.el.removeObject3D('mesh');
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
    const oldRings = document.querySelector('#radar-ground-rings');
    const oldRadar = document.querySelector('#radar-sensors');
    oldRings?.parentNode?.removeChild(oldRings);
    oldRadar?.parentNode?.removeChild(oldRadar);
    if (!renderRadar) return;
    sceneEl.appendChild(this.createRadarGroundRings());
    sceneEl.appendChild(this.createRadarSensors());
  }
}

export default makeHook(Pixels3dAframeHook);
