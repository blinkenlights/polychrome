import { Hook, makeHook } from "phoenix_typed_hook";

type RGB = [number, number, number];
type Frame = { kind: "rgb"; data: number[] };

import * as THREE from "three";

import Stats from "three/addons/libs/stats.module.js";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";

import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { RectAreaLightHelper } from "three/addons/helpers/RectAreaLightHelper.js";
import { RectAreaLightUniformsLib } from "three/addons/lights/RectAreaLightUniformsLib.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

const vertexShader = `
  varying vec2 vUv;

  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
  }
`;

const fragmentShader = `
  uniform sampler2D uLEDTexture;
  varying vec2 vUv;

  void main() {
    vec2 texCoord = floor(vec2(vUv.x, 1.0 - vUv.y) * 8.0) / 8.0 + vec2(0.5 / 8.0); // snap to LED cell
    vec3 color = texture2D(uLEDTexture, texCoord).rgb;
    gl_FragColor = vec4(color, 1.0);
  }
`;

class Pixels3dHook extends Hook {
  mounted() {
    const canvas = this.el as HTMLCanvasElement;
    const id = canvas.id;
    let pixelOffset = 0;

    let pixels: RGB[] = [];

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.el.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(
      75,
      window.innerWidth / window.innerHeight,
      0.1,
      1000
    );
    camera.position.set(0, 5, -15);

    const panels = 10;
    const textures: THREE.DataTexture[] = [];
    const materials: THREE.ShaderMaterial[] = [];
    const meshes: THREE.Mesh[] = [];

    for (let i = 0; i < panels; i++) {
      const data = new Uint8Array(8 * 8 * 4);
      for (let j = 0; j < data.length; j += 4) {
        data[j] = Math.floor(0);
        data[j + 1] = Math.floor(0);
        data[j + 2] = Math.floor(0);
        data[j + 3] = 255;
      }

      const texture = new THREE.DataTexture(data, 8, 8, THREE.RGBAFormat);
      texture.needsUpdate = true;
      textures.push(texture);

      const uniforms = {
        uLEDTexture: { value: texture },
      };

      const material = new THREE.ShaderMaterial({
        uniforms,
        vertexShader,
        fragmentShader,
      });
      materials.push(material);

      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(8, 8), material);
      const radius = 20;
      const angle = (i / panels) * Math.PI * 2;
      mesh.position.set(radius * Math.sin(angle), 4, radius * Math.cos(angle));
      mesh.rotation.y = angle + Math.PI;
      meshes.push(mesh);
      scene.add(mesh);
    }

    scene.add(new THREE.AmbientLight(0xffffff, 0.1));

    const geoFloor = new THREE.BoxGeometry(2000, 0.1, 2000);
    const matStdFloor = new THREE.MeshStandardMaterial({
      color: 0xbcbcbc,
      roughness: 0.1,
      metalness: 0,
    });
    const mshStdFloor = new THREE.Mesh(geoFloor, matStdFloor);
    scene.add(mshStdFloor);

    const geoKnot = new THREE.TorusKnotGeometry(1.5, 0.5, 200, 16);
    const matKnot = new THREE.MeshStandardMaterial({
      color: 0xffffff,
      roughness: 0,
      metalness: 0,
    });
    const meshKnot = new THREE.Mesh(geoKnot, matKnot);
    meshKnot.position.set(0, 5, 0);
    // scene.add(meshKnot);

    const controls = new OrbitControls(camera, renderer.domElement);
    // controls.target.copy(meshKnot.position);
    controls.target.copy(new THREE.Vector3(0, 4, 0));
    controls.update();

    window.addEventListener("resize", onWindowResize);

    const stats = new Stats();
    document.body.appendChild(stats.dom);

    const renderScene = new RenderPass(scene, camera);

    const params = {
      threshold: 0,
      strength: 1,
      radius: 0,
      exposure: 0.6,
      tonemapping: "ACESFilmicToneMapping",
    };

    const bloomPass = new UnrealBloomPass(
      new THREE.Vector2(window.innerWidth, window.innerHeight),
      1.5,
      0.4,
      0.85
    );
    bloomPass.threshold = params.threshold;
    bloomPass.strength = params.strength;
    bloomPass.radius = params.radius;
    renderer.toneMappingExposure = Math.pow(params.exposure, 4.0);
    const outputPass = new OutputPass();

    const composer = new EffectComposer(renderer);
    composer.addPass(renderScene);
    composer.addPass(bloomPass);
    composer.addPass(outputPass);

    const gui = new GUI();

    const bloomFolder = gui.addFolder("bloom");

    bloomFolder.add(params, "threshold", 0.0, 1.0).onChange(function (value) {
      bloomPass.threshold = Number(value);
    });

    bloomFolder.add(params, "strength", 0.0, 3.0).onChange(function (value) {
      bloomPass.strength = Number(value);
    });

    bloomFolder.add(params, "radius", 0.0, 1.0).onChange(function (value) {
      bloomPass.radius = Number(value);
    });

    const toneMappingFolder = gui.addFolder("tone mapping");

    toneMappingFolder
      .add(params, "exposure", 0.1, 2)
      .onChange(function (value) {
        renderer.toneMappingExposure = Math.pow(value, 4.0);
      });

    toneMappingFolder
      .add(
        params,
        "tonemapping",

        [
          "NoToneMapping",
          "LinearToneMapping",
          "ReinhardToneMapping",
          "CineonToneMapping",
          "ACESFilmicToneMapping",
          "CustomToneMapping",
          "AgXToneMapping",
          "NeutralToneMapping",
        ]
      )
      .onChange(function (value) {
        console.log(value);
        switch (value) {
          case "NoToneMapping":
            renderer.toneMapping = THREE.NoToneMapping;
            break;
          case "LinearToneMapping":
            renderer.toneMapping = THREE.LinearToneMapping;
            break;
          case "ReinhardToneMapping":
            renderer.toneMapping = THREE.ReinhardToneMapping;
            break;
          case "CineonToneMapping":
            renderer.toneMapping = THREE.CineonToneMapping;
            break;
          case "ACESFilmicToneMapping":
            renderer.toneMapping = THREE.ACESFilmicToneMapping;
            break;
          case "CustomToneMapping":
            renderer.toneMapping = THREE.CustomToneMapping;
            break;
          case "AgXToneMapping":
            renderer.toneMapping = THREE.AgXToneMapping;
            break;
          case "NeutralToneMapping":
            renderer.toneMapping = THREE.NeutralToneMapping;
          default:
            renderer.toneMapping = THREE.NoToneMapping;
        }
      });

    function onWindowResize() {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
      composer.setSize(window.innerWidth, window.innerHeight);
    }

    function animate(time: DOMHighResTimeStamp) {
      meshKnot.rotation.y = time / 1000;
      stats.update();

      for (let i = 0; i < panels; i++) {
        for (let j = 0; j < 64; j++) {
          let textureIdx = panels - i - 1;
          const pixelIdx = i * 64 + j;
          textures[textureIdx].image.data[j * 4] = pixels[pixelIdx][0];
          textures[textureIdx].image.data[j * 4 + 1] = pixels[pixelIdx][1];
          textures[textureIdx].image.data[j * 4 + 2] = pixels[pixelIdx][2];
          textures[textureIdx].image.data[j * 4 + 3] = 255;
          textures[textureIdx].needsUpdate = true;
        }
      }

      composer.render();
    }
    renderer.setAnimationLoop(animate);

    [`frame:${id}`, "frame:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ frame: frame }: { frame: Frame }) => {
        switch (frame.kind) {
          case "rgb": {
            const numPixels = frame.data.length / 3;
            pixels = pixels.slice(0, numPixels);
            for (let i = 0; i < numPixels; i++) {
              const pixelOffset = i * 3;
              const r = frame.data[pixelOffset];
              const g = frame.data[pixelOffset + 1];
              const b = frame.data[pixelOffset + 2];

              pixels[i] = [r, g, b];
            }
            break;
          }
          default: {
            throw new Error("Unsupported frame kind: " + frame.kind);
          }
        }
      });
    });
  }
}

export default makeHook(Pixels3dHook);
