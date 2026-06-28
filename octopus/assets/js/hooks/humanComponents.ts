/**
 * A-Frame components that bridge the framework-free `HumanWorld` model into
 * a renderable scene. Two components:
 *
 *   - `humans-root`   — singleton, owns the HumanWorld instance, ticks it,
 *                       and syncs child <a-entity human-marker> entities.
 *   - `human-marker`  — single avatar (cylinder body + sphere head + heading
 *                       arrow). Lerps smoothly toward target pose.
 *
 * `pixels3daframe.ts` ships its own copy of THREE (A-Frame bundles ~r173).
 * Mirroring the convention here so the two never disagree.
 */

import AFRAME from "aframe";
import { HumanWorld, Human, colorForId } from "./humanWorld";

function getThree() {
  return (AFRAME as any).THREE;
}

let humanWorldSingleton: HumanWorld | null = null;

export function getHumanWorld(): HumanWorld | null {
  return humanWorldSingleton;
}

let registered = false;

export function registerHumanComponents() {
  if (registered) return;
  registered = true;

  AFRAME.registerComponent("humans-root", {
    schema: {},
    init: function (this: any) {
      this.knownIds = new Set<string>();
      humanWorldSingleton = new HumanWorld();
    },
    tick: function (this: any, _t: number, _dtMs: number) {
      const world = humanWorldSingleton;
      if (!world) return;
      this.syncChildren(world);
    },
    syncChildren: function (this: any, world: HumanWorld) {
      const seen = new Set<string>();
      for (const human of world.humans.values()) {
        seen.add(human.id);
        let child = this.el.querySelector(`[data-human-id="${human.id}"]`) as any;
        if (!child) {
          child = document.createElement("a-entity");
          child.setAttribute("data-human-id", human.id);
          child.setAttribute("human-marker", buildMarkerData(human));
          this.el.appendChild(child);
          this.knownIds.add(human.id);
        } else {
          child.setAttribute("human-marker", buildMarkerData(human));
        }
      }
      // Remove markers whose human despawned.
      for (const id of this.knownIds) {
        if (!seen.has(id)) {
          const stale = this.el.querySelector(`[data-human-id="${id}"]`);
          stale?.parentNode?.removeChild(stale);
          this.knownIds.delete(id);
        }
      }
    },
    remove: function (this: any) {
      humanWorldSingleton = null;
      this.knownIds?.clear?.();
    },
  });

  AFRAME.registerComponent("human-marker", {
    schema: {
      x: { type: "number", default: 0 },
      z: { type: "number", default: 0 },
      heading: { type: "number", default: 0 },
      height: { type: "number", default: 1.7 },
      color: { type: "string", default: "#ccc" },
    },
    init: function (this: {
      el: any;
      data: any;
      group: any;
      currentHeading: number;
    }) {
      const T = getThree();
      const height = this.data.height;
      const bodyHeight = Math.max(0.4, height - 0.25);

      const group = new T.Group();

      const bodyMat = new T.MeshStandardMaterial({
        color: new T.Color(this.data.color),
        roughness: 0.75,
        metalness: 0.0,
      });
      const body = new T.Mesh(
        new T.CylinderGeometry(0.18, 0.18, bodyHeight, 16),
        bodyMat
      );
      body.position.y = bodyHeight / 2;
      body.castShadow = true;
      group.add(body);

      const headMat = new T.MeshStandardMaterial({
        color: new T.Color(this.data.color).offsetHSL(0, 0, 0.1),
        roughness: 0.55,
        metalness: 0.0,
      });
      const head = new T.Mesh(
        new T.SphereGeometry(0.12, 20, 14),
        headMat
      );
      // Head sits just above the cylinder body.
      head.position.y = bodyHeight + 0.12;
      head.castShadow = true;
      group.add(head);

      // Heading arrow — flat triangle laid on the ground, tip pointing in +Z.
      // Marker yaw lives on `group.rotation.y`, so the arrow co-rotates with
      // the body. Kept low to the floor so it reads as a footprint indicator
      // rather than a body-mounted protrusion.
      const arrowShape = new T.Shape();
      arrowShape.moveTo(-0.12, -0.14);
      arrowShape.lineTo(0.12, -0.14);
      arrowShape.lineTo(0, 0.2);
      arrowShape.lineTo(-0.12, -0.14);
      const arrowMat = new T.MeshStandardMaterial({
        color: new T.Color(this.data.color).offsetHSL(0, 0.1, -0.2),
        roughness: 0.6,
        side: T.DoubleSide,
      });
      const arrow = new T.Mesh(new T.ShapeGeometry(arrowShape), arrowMat);
      arrow.rotation.x = Math.PI / 2;
      arrow.position.set(0, 0.02, 0.05);
      group.add(arrow);

      this.group = group;
      this.el.setObject3D("mesh", group);

      this.el.object3D.position.set(this.data.x, 0, this.data.z);
      this.el.object3D.rotation.y = this.data.heading;
      this.currentHeading = this.data.heading;
    },
    update: function (
      this: { data: any; oldData: any; group: any; el: any },
      oldData: any
    ) {
      // Rebuild the mesh only when an immutable visual prop changes.
      if (
        oldData &&
        Object.keys(oldData).length > 0 &&
        (oldData.color !== this.data.color || oldData.height !== this.data.height)
      ) {
        this.el.removeObject3D("mesh");
        // Re-run init logic to rebuild with new color/height.
        (this as any).init();
      }
    },
    tick: function (
      this: {
        el: any;
        data: { x: number; z: number; heading: number };
        currentHeading: number;
      },
      _t: number,
      dtMs: number
    ) {
      const dt = Math.max(0, Math.min(0.25, dtMs / 1000));
      const obj = this.el.object3D;

      // Position lerp — exponential smoothing to target.
      const k = 1 - Math.exp(-12 * dt);
      obj.position.x += (this.data.x - obj.position.x) * k;
      obj.position.z += (this.data.z - obj.position.z) * k;
      obj.position.y = 0;

      // Rotation lerp — shortest-path around Y.
      const target = this.data.heading;
      let diff = target - this.currentHeading;
      while (diff > Math.PI) diff -= 2 * Math.PI;
      while (diff <= -Math.PI) diff += 2 * Math.PI;
      this.currentHeading += diff * k;
      obj.rotation.y = this.currentHeading;
    },
    remove: function (this: { el: any }) {
      this.el.removeObject3D("mesh");
    },
  });
}

function buildMarkerData(human: Human): string {
  // A-Frame component literal — values get parsed by the schema parser.
  return [
    `x: ${human.pos.x.toFixed(4)}`,
    `z: ${human.pos.z.toFixed(4)}`,
    `heading: ${human.heading.toFixed(4)}`,
    `height: ${human.height.toFixed(3)}`,
    `color: ${human.color}`,
  ].join("; ");
}

// Re-export so the hook can pick up colorForId without an extra import line.
export { colorForId };
