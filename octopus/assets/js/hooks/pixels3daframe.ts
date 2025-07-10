import { Hook, makeHook } from "phoenix_typed_hook";

type RGB = [number, number, number];

import { Frame, rgbPixelsFromFrame } from "./shared/frame";

import * as THREE from "three";

import { VRButton } from "three/addons/webxr/VRButton.js";
import { PointerLockControls } from "three/addons/controls/PointerLockControls.js";
import Stats from "three/addons/libs/stats.module.js";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

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

const PANEL_SIZE = 1.6;
const PANEL_DEPTH = 0.3;

class Pixels3dAframeHook extends Hook {
  mounted() {
    const canvas = this.el as HTMLCanvasElement;
    const id = canvas.id;
    const numPanels = parseInt(this.el.getAttribute("num-panels") || "10");

    const textures: THREE.DataTexture[] = [];
    const frontMaterials: THREE.ShaderMaterial[] = [];
    const backMaterials: THREE.ShaderMaterial[] = [];
    const panels: THREE.Object3D[] = [];
    const poles: { mesh: THREE.Mesh; geometry: THREE.CylinderGeometry }[] = [];
    const feet: { mesh: THREE.Mesh; geometry: THREE.CylinderGeometry }[] = [];
    const buttonPoles: THREE.Mesh[] = [];
    const buttonBases: THREE.Mesh[] = [];
    const buttonRings: THREE.Mesh[] = [];
    const buttonDomes: THREE.Mesh[] = [];
    const pixels: RGB[] = Array(numPanels * 8 * 8).fill([0, 0, 0]);
    let diameter = 20.0;
    let height = 0.4;
    let footDiameter = 0.3;
    let poleDiameter = 0.15;
    let buttonPolesDiameter = 6.0; // 6m diameter for button poles circle

    // Button poles configuration
    const numButtonPoles = 12;
    const buttonPoleHeight = 1.0; // 100cm
    const buttonPoleDiameter = 0.1; // 10cm

    // Button components configuration
    const buttonBaseDiameter = 0.1; // 10cm
    const buttonBaseHeight = 0.0175; // 17.5mm
    const buttonRingDiameter = 0.1; // 10cm
    const buttonRingHeight = 0.008; // 8mm
    const buttonDomeDiameter = 0.09; // 9cm

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.xr.enabled = true;
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.el.appendChild(renderer.domElement);
    document.body.appendChild(VRButton.createButton(renderer));

    const scene = new THREE.Scene();

    const skyGeometry = new THREE.SphereGeometry(1000, 32, 32);
    const skyMaterial = new THREE.ShaderMaterial({
      vertexShader: skyVertexShader,
      fragmentShader: skyFragmentShader,
      side: THREE.BackSide,
    });
    const skySphere = new THREE.Mesh(skyGeometry, skyMaterial);
    skySphere.castShadow = false;
    skySphere.receiveShadow = false;
    skyMaterial.depthWrite = false;
    scene.add(skySphere);

    const camera = new THREE.PerspectiveCamera(
      75,
      window.innerWidth / window.innerHeight,
      0.1,
      10000
    );

    const moveInput = new THREE.Vector2();
    let vrMovementObject: THREE.Object3D;

    const controls = new PointerLockControls(camera, renderer.domElement);
    controls.object.position.set(0, 1.8, 0);
    scene.add(controls.object);

    vrMovementObject = new THREE.Object3D();
    scene.add(vrMovementObject);

    canvas.addEventListener("click", () => {
      if (!controls.isLocked) {
        controls.lock();
      }
    });

    document.addEventListener("keydown", (event) => {
      switch (event.code) {
        case "ArrowUp":
        case "KeyW":
          moveInput.y = 1;
          break;

        case "ArrowLeft":
        case "KeyA":
          moveInput.x = -1;
          break;

        case "ArrowDown":
        case "KeyS":
          moveInput.y = -1;
          break;

        case "ArrowRight":
        case "KeyD":
          moveInput.x = 1;
          break;
      }
    });

    document.addEventListener("keyup", (event) => {
      switch (event.code) {
        case "ArrowUp":
        case "KeyW":
          moveInput.y = 0;
          break;

        case "ArrowLeft":
        case "KeyA":
          moveInput.x = 0;
          break;

        case "ArrowDown":
        case "KeyS":
          moveInput.y = 0;
          break;

        case "ArrowRight":
        case "KeyD":
          moveInput.x = 0;
          break;
      }
    });

    const updateMeshes = () => {
      for (let i = 0; i < numPanels; i++) {
        const panel = panels[i];
        const radius = diameter / 2;
        const angle = (i / numPanels) * Math.PI * 2;
        panel.position.set(
          radius * Math.sin(angle),
          PANEL_SIZE / 2 + height,
          radius * Math.cos(angle)
        );
        panel.rotation.y = angle + Math.PI;

        const poleLeft = poles[i * 2];
        const poleRight = poles[i * 2 + 1];
        poleLeft.mesh.position.set(
          -PANEL_SIZE / 2 + poleDiameter / 2,
          -height / 2,
          -PANEL_DEPTH - poleDiameter / 2
        );
        poleRight.mesh.position.set(
          PANEL_SIZE / 2 - poleDiameter / 2,
          -height / 2,
          -PANEL_DEPTH - poleDiameter / 2
        );
        poleLeft.mesh.geometry = new THREE.CylinderGeometry(
          poleDiameter / 2,
          poleDiameter / 2,
          PANEL_SIZE + height,
          16
        );
        poleRight.mesh.geometry = new THREE.CylinderGeometry(
          poleDiameter / 2,
          poleDiameter / 2,
          PANEL_SIZE + height,
          16
        );

        const footLeft = feet[i * 2];
        const footRight = feet[i * 2 + 1];
        footLeft.mesh.position.set(
          -PANEL_SIZE / 2 + footDiameter / 2,
          -PANEL_SIZE / 2 - height / 2,
          -PANEL_DEPTH / 2
        );
        footRight.mesh.position.set(
          PANEL_SIZE / 2 - footDiameter / 2,
          -PANEL_SIZE / 2 - height / 2,
          -PANEL_DEPTH / 2
        );
        footLeft.mesh.geometry = new THREE.CylinderGeometry(
          footDiameter / 2,
          footDiameter / 2,
          height,
          16
        );
        footRight.mesh.geometry = new THREE.CylinderGeometry(
          footDiameter / 2,
          footDiameter / 2,
          height,
          16
        );
      }

      // Update button poles positions - align with panels
      const buttonPoleRadius = buttonPolesDiameter / 2;
      for (let i = 0; i < buttonPoles.length; i++) {
        const angle = (i / numButtonPoles) * Math.PI * 2;
        buttonPoles[i].position.set(
          buttonPoleRadius * Math.sin(angle),
          buttonPoleHeight / 2, // Half height to position bottom at ground level
          buttonPoleRadius * Math.cos(angle)
        );
      }

      // Update button components positions
      const buttonTopY = buttonPoleHeight;
      for (let i = 0; i < buttonBases.length; i++) {
        const angle = (i / numButtonPoles) * Math.PI * 2;
        const x = buttonPoleRadius * Math.sin(angle);
        const z = buttonPoleRadius * Math.cos(angle);

        // Update button base position
        buttonBases[i].position.set(x, buttonTopY + buttonBaseHeight / 2, z);

        // Update button ring position
        buttonRings[i].position.set(
          x,
          buttonTopY + buttonBaseHeight + buttonRingHeight / 2,
          z
        );

        // Update button dome position
        buttonDomes[i].position.set(
          x,
          buttonTopY + buttonBaseHeight + buttonRingHeight,
          z
        );
      }
    };

    // Create shared wood material for all poles
    const woodMaterial = new THREE.MeshStandardMaterial({
      color: 0x8b4513,
      roughness: 0.9,
      metalness: 0.0,
    });

    // Create materials for button components
    const blackButtonMaterial = new THREE.MeshStandardMaterial({
      color: 0x000000,
      roughness: 0.3,
      metalness: 0.1,
    });

    const redButtonMaterial = new THREE.MeshStandardMaterial({
      color: 0xff0000,
      roughness: 0.2,
      metalness: 0.0,
    });

    for (let i = 0; i < numPanels; i++) {
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

      const frontUniforms = {
        uLEDTexture: { value: texture },
        uMask: { value: 0.2 },
        uMaskSmoothness: { value: 1.0 },
        uMaskSize: { value: 1.0 },
      };

      const backUniforms = {
        uLEDTexture: { value: texture },
        uMask: { value: 1.0 },
        uMaskSmoothness: { value: 0.05 },
        uMaskSize: { value: 0.1 },
      };

      const frontMaterial = new THREE.ShaderMaterial({
        uniforms: frontUniforms,
        vertexShader,
        fragmentShader,
      });
      frontMaterials.push(frontMaterial);

      const backMaterial = new THREE.ShaderMaterial({
        uniforms: backUniforms,
        vertexShader,
        fragmentShader,
      });
      backMaterials.push(backMaterial);

      const frontMesh = new THREE.Mesh(
        new THREE.PlaneGeometry(PANEL_SIZE, PANEL_SIZE),
        frontMaterial
      );

      const backMesh = new THREE.Mesh(
        new THREE.PlaneGeometry(PANEL_SIZE, PANEL_SIZE),
        backMaterial
      );

      backMesh.rotateY(Math.PI);
      backMesh.translateZ(PANEL_DEPTH);

      const centerMeshGeo = new THREE.BoxGeometry(
        PANEL_SIZE,
        PANEL_SIZE,
        PANEL_DEPTH
      );
      const centerMeshMat = new THREE.MeshStandardMaterial({
        color: 0xffffff,
        roughness: 0.4,
      });
      const centerMesh = new THREE.Mesh(centerMeshGeo, centerMeshMat);
      centerMesh.translateZ(-PANEL_DEPTH / 2);
      centerMesh.scale.set(1.0, 1.0, 0.95);

      const poleGeometry = new THREE.CylinderGeometry();
      const poleLeft = new THREE.Mesh(poleGeometry, woodMaterial);
      const poleRight = new THREE.Mesh(poleGeometry, woodMaterial);

      const footGeometry = new THREE.CylinderGeometry();
      const footLeft = new THREE.Mesh(footGeometry, woodMaterial);
      const footRight = new THREE.Mesh(footGeometry, woodMaterial);

      poles.push({ mesh: poleLeft, geometry: poleGeometry });
      poles.push({ mesh: poleRight, geometry: poleGeometry });
      feet.push({ mesh: footLeft, geometry: footGeometry });
      feet.push({ mesh: footRight, geometry: footGeometry });

      const obj = new THREE.Object3D();
      obj.add(frontMesh);
      obj.add(backMesh);
      obj.add(centerMesh);
      obj.add(poleLeft);
      obj.add(poleRight);
      obj.add(footLeft);
      obj.add(footRight);

      panels.push(obj);
      vrMovementObject.add(obj);
    }

    updateMeshes();

    // Create 12 button poles in circular arrangement
    for (let i = 0; i < numButtonPoles; i++) {
      const angle = (i / numButtonPoles) * Math.PI * 2;
      const buttonPoleRadius = buttonPolesDiameter / 2;

      const buttonPoleGeometry = new THREE.CylinderGeometry(
        buttonPoleDiameter / 2,
        buttonPoleDiameter / 2,
        buttonPoleHeight,
        16
      );

      const buttonPole = new THREE.Mesh(buttonPoleGeometry, woodMaterial);

      buttonPole.position.set(
        buttonPoleRadius * Math.sin(angle),
        buttonPoleHeight / 2, // Half height to position bottom at ground level
        buttonPoleRadius * Math.cos(angle)
      );

      buttonPoles.push(buttonPole);
      vrMovementObject.add(buttonPole);

      // Create button components on top of each pole
      const buttonTopY = buttonPoleHeight;

      // Button base (black cylinder)
      const buttonBaseGeometry = new THREE.CylinderGeometry(
        buttonBaseDiameter / 2,
        buttonBaseDiameter / 2,
        buttonBaseHeight,
        32
      );
      const buttonBase = new THREE.Mesh(
        buttonBaseGeometry,
        blackButtonMaterial
      );
      buttonBase.position.set(
        buttonPoleRadius * Math.sin(angle),
        buttonTopY + buttonBaseHeight / 2,
        buttonPoleRadius * Math.cos(angle)
      );

      // Button ring (black cylindrical ring - simplified as solid cylinder)
      const buttonRingGeometry = new THREE.CylinderGeometry(
        buttonRingDiameter / 2,
        buttonRingDiameter / 2,
        buttonRingHeight,
        32
      );
      const buttonRing = new THREE.Mesh(
        buttonRingGeometry,
        blackButtonMaterial
      );
      buttonRing.position.set(
        buttonPoleRadius * Math.sin(angle),
        buttonTopY + buttonBaseHeight + buttonRingHeight / 2,
        buttonPoleRadius * Math.cos(angle)
      );

      // Button dome (red hemisphere)
      const buttonDomeGeometry = new THREE.SphereGeometry(
        buttonDomeDiameter / 2,
        32,
        16,
        0,
        Math.PI * 2,
        0,
        Math.PI / 2 // Only upper hemisphere
      );
      const buttonDome = new THREE.Mesh(buttonDomeGeometry, redButtonMaterial);
      buttonDome.position.set(
        buttonPoleRadius * Math.sin(angle),
        buttonTopY + buttonBaseHeight + buttonRingHeight,
        buttonPoleRadius * Math.cos(angle)
      );

      buttonBases.push(buttonBase);
      buttonRings.push(buttonRing);
      buttonDomes.push(buttonDome);

      vrMovementObject.add(buttonBase);
      vrMovementObject.add(buttonRing);
      vrMovementObject.add(buttonDome);
    }

    const light = new THREE.HemisphereLight(0xb0c4de, 0x556b2f, 0.5);
    light.position.set(0.5, 1, 0.75);
    vrMovementObject.add(light);

    const textureLoader = new THREE.TextureLoader();
    const groundAlbedoTexture = textureLoader.load(
      "/images/patchy-meadow1/patchy-meadow1_albedo.png"
    );
    const groundRoughnessTexture = textureLoader.load(
      "/images/patchy-meadow1/patchy-meadow1_roughness.png"
    );
    const groundNormalTexture = textureLoader.load(
      "/images/patchy-meadow1/patchy-meadow1_normal-ogl.png"
    );

    groundAlbedoTexture.wrapS = groundAlbedoTexture.wrapT =
      THREE.RepeatWrapping;
    groundRoughnessTexture.wrapS = groundRoughnessTexture.wrapT =
      THREE.RepeatWrapping;
    groundNormalTexture.wrapS = groundNormalTexture.wrapT =
      THREE.RepeatWrapping;

    const textureRepeat = 1000;
    groundAlbedoTexture.repeat.set(textureRepeat, textureRepeat);
    groundRoughnessTexture.repeat.set(textureRepeat, textureRepeat);
    groundNormalTexture.repeat.set(textureRepeat, textureRepeat);

    const groundGeometry = new THREE.PlaneGeometry(2000, 2000);
    groundGeometry.rotateX(-Math.PI / 2);
    const groundMaterial = new THREE.MeshStandardMaterial({
      map: groundAlbedoTexture,
      roughnessMap: groundRoughnessTexture,
      normalMap: groundNormalTexture,
      normalScale: new THREE.Vector2(1, 1),
      metalness: 0.0,
    });
    const groundMesh = new THREE.Mesh(groundGeometry, groundMaterial);
    vrMovementObject.add(groundMesh);

    // Load second human model next to a panel
    const gltfLoader = new GLTFLoader();
    gltfLoader.load(
      "/models/low_poly_character/scene.gltf",
      (gltf) => {
        const human2 = gltf.scene.clone();

        // Use natural model size (no scaling)

        // Position next to the first LED panel (panel 0)
        const panelRadius = diameter / 2;
        const panelAngle = 0; // First panel angle
        const offsetDistance = 3.0; // 3 meters away from the panel

        human2.position.set(
          (panelRadius + offsetDistance) * Math.sin(panelAngle),
          0,
          (panelRadius + offsetDistance) * Math.cos(panelAngle)
        );

        // Rotate to face the panel
        human2.rotation.y = panelAngle + Math.PI;

        // Add to the scene
        vrMovementObject.add(human2);

        console.log("Second human model added next to panel");
      },
      undefined,
      (error) => {
        console.error("Error loading second human model:", error);
      }
    );

    window.addEventListener("resize", onWindowResize);

    const stats = new Stats();
    document.body.appendChild(stats.dom);

    const params = {
      exposure: 1.0,
    };
    renderer.toneMappingExposure = Math.pow(params.exposure, 4.0);

    const gui = new GUI();

    gui
      .addFolder("Tonemapping")
      .add(params, "exposure", 0.1, 2)
      .onChange(function (value) {
        renderer.toneMappingExposure = Math.pow(value, 4.0);
      });

    function onWindowResize() {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
    }

    var lastTime = performance.now();

    function animate(time: DOMHighResTimeStamp) {
      const delta = (time - lastTime) * 0.001;
      lastTime = time;

      if (!renderer.xr.isPresenting) {
        controls.moveForward(moveInput.normalize().y * delta * 4.0);
        controls.moveRight(moveInput.normalize().x * delta * 4.0);
      } else {
        const moveSpeed = delta * 4.0;
        const normalizedInput = moveInput.normalize();

        if (normalizedInput.length() > 0) {
          const xrCamera = renderer.xr.getCamera();

          const forward = new THREE.Vector3(0, 0, -1);
          forward.applyQuaternion(xrCamera.quaternion);
          forward.y = 0;
          forward.normalize();

          const right = new THREE.Vector3(1, 0, 0);
          right.applyQuaternion(xrCamera.quaternion);
          right.y = 0;
          right.normalize();

          const movement = new THREE.Vector3();
          movement.addScaledVector(forward, normalizedInput.y * moveSpeed);
          movement.addScaledVector(right, normalizedInput.x * moveSpeed);

          vrMovementObject.position.sub(movement);
        }
      }

      stats.update();

      for (let i = 0; i < numPanels; i++) {
        for (let j = 0; j < 64; j++) {
          let textureIdx = numPanels - i - 1;
          const pixelIdx = i * 64 + j;
          if (pixels[pixelIdx]) {
            textures[textureIdx].image.data[j * 4] = pixels[pixelIdx][0];
            textures[textureIdx].image.data[j * 4 + 1] = pixels[pixelIdx][1];
            textures[textureIdx].image.data[j * 4 + 2] = pixels[pixelIdx][2];
            textures[textureIdx].image.data[j * 4 + 3] = 255;
            textures[textureIdx].needsUpdate = true;
          }
        }
      }

      renderer.render(scene, camera);
    }

    renderer.setAnimationLoop(animate);

    type Param = {
      param: {
        diameter?: number;
        move?: [number, number];
        position?: [number, number];
        height?: number;
        pole_diameter?: number;
        foot_diameter?: number;
        button_poles_diameter?: number;
      };
    };

    this.handleEvent(`param:${id}`, ({ param: param }: Param) => {
      if (param.diameter) {
        diameter = param.diameter;
        updateMeshes();
      }
      if (param.move) {
        moveInput.set(param.move[0], param.move[1]);
      }
      if (param.position) {
        if (!renderer.xr.isPresenting) {
          camera.position.set(
            param.position[0],
            camera.position.y,
            -param.position[1]
          );
        } else {
          const y = vrMovementObject.position.y;
          vrMovementObject.position.set(
            -param.position[0],
            y,
            param.position[1]
          );
        }
      }
      if (param.height) {
        height = param.height;
        updateMeshes();
      }
      if (param.pole_diameter) {
        poleDiameter = param.pole_diameter;
        updateMeshes();
      }
      if (param.foot_diameter) {
        footDiameter = param.foot_diameter;
        updateMeshes();
      }
      if (param.button_poles_diameter) {
        buttonPolesDiameter = param.button_poles_diameter;
        updateMeshes();
      }
    });

    [`frame:${id}`, "frame:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ frame: frame }: { frame: Frame }) => {
        for (let [i, pixel] of rgbPixelsFromFrame(frame).entries()) {
          pixels[i] = pixel;
        }
      });
    });
  }
}

export default makeHook(Pixels3dAframeHook);
