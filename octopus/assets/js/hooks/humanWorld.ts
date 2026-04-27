/**
 * HumanWorld — purely client-side mock of people walking around the installation.
 *
 * Coordinate system: A-Frame world frame. Y is up, ground is the X/Z plane.
 * The model is intentionally framework-free (no A-Frame / Three imports), so the
 * same logic can later be lifted into an Elixir GenServer without changes.
 */

export type HumanMode = "wander" | "approach";

export type Human = {
  id: string;
  pos: { x: number; z: number };
  prevPos: { x: number; z: number };
  heading: number;
  speed: number;
  height: number;
  color: string;
  mode: HumanMode;
  waypoint: { x: number; z: number };
  /** ms timestamp; 0 means active */
  idleUntilMs: number;
  spawnedAtMs: number;
  /** velocity vector in m/s (world frame, X/Z) — derived each tick */
  vel: { x: number; z: number };
};

export type SensorPose = {
  /** world position in meters */
  pos: [number, number, number];
  yawRad: number;
  tiltRad: number;
};

export type SensorFov = {
  /** full horizontal FoV in radians */
  hRad: number;
  /** full vertical FoV in radians */
  vRad: number;
  /** max detectable distance in meters */
  rangeM: number;
};

export type DetectedTarget = {
  id: string;
  distance: number;
  /** signed azimuth, 0 = forward, +X = right, in radians */
  azimuth: number;
  /** signed elevation, 0 = forward, +Y = up, in radians */
  elevation: number;
  /** radial velocity (Doppler), m/s, positive = moving away */
  velocityRadial: number;
  /** position in sensor-local frame: X right, Y up, Z forward (along cone axis) */
  posLocal: [number, number, number];
};

const DEFAULT_COUNT = 5;
const DEFAULT_SPEED_MULT = 1.0;
const DEFAULT_MODE: HumanMode = "wander";
const HUMAN_HEIGHT_M = 1.7;
const INNER_RADIUS_M = 1.5;
const OUTER_RADIUS_M_FALLBACK = 11.0;
const SPEED_MIN = 0.8;
const SPEED_MAX = 1.4;
const HEADING_LERP = 4.0;
const WAYPOINT_REACHED_M = 0.3;
const IDLE_MS_MIN = 800;
const IDLE_MS_MAX = 3000;
const APPROACH_IDLE_MS_MIN = 5000;
const APPROACH_IDLE_MS_MAX = 15000;
const APPROACH_OUTER_PAD_M = 0.5;

export type HumanWorldOptions = {
  count?: number;
  speedMult?: number;
  mode?: HumanMode;
  paused?: boolean;
  panelDiameter?: number;
};

/** Stable, light-touch hash → 0..1, used for deterministic per-id colors. */
function hashStringToUnit(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  // unsigned + normalize
  return ((h >>> 0) % 1000000) / 1000000;
}

export function colorForId(id: string): string {
  const h = Math.floor(hashStringToUnit(id) * 360);
  return `hsl(${h}, 55%, 55%)`;
}

function uniform(min: number, max: number): number {
  return min + Math.random() * (max - min);
}

function distance2D(a: { x: number; z: number }, b: { x: number; z: number }): number {
  const dx = a.x - b.x;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dz * dz);
}

/** Wrap an angle to (-π, π]. */
function wrapAngle(a: number): number {
  let v = a;
  while (v > Math.PI) v -= 2 * Math.PI;
  while (v <= -Math.PI) v += 2 * Math.PI;
  return v;
}

/** Move `from` toward `to` by at most `step`, returning new value. */
function lerpAngle(from: number, to: number, step: number): number {
  const diff = wrapAngle(to - from);
  if (Math.abs(diff) <= step) return wrapAngle(to);
  return wrapAngle(from + Math.sign(diff) * step);
}

export class HumanWorld {
  humans: Map<string, Human> = new Map();
  private nextHumanIndex = 1;
  private targetCount: number;
  private speedMult: number;
  private mode: HumanMode;
  private paused: boolean;
  private innerRadiusM: number = INNER_RADIUS_M;
  private outerRadiusM: number = OUTER_RADIUS_M_FALLBACK;

  constructor(opts: HumanWorldOptions = {}) {
    this.targetCount = Math.max(0, Math.floor(opts.count ?? DEFAULT_COUNT));
    this.speedMult = Math.max(0, opts.speedMult ?? DEFAULT_SPEED_MULT);
    this.mode = opts.mode ?? DEFAULT_MODE;
    this.paused = !!opts.paused;
    if (typeof opts.panelDiameter === "number") {
      this.setBounds(opts.panelDiameter);
    }
    this.maintainPopulation();
  }

  setCount(n: number) {
    this.targetCount = Math.max(0, Math.floor(n));
    this.maintainPopulation();
  }

  setSpeed(mult: number) {
    this.speedMult = Math.max(0, mult);
  }

  setPaused(p: boolean) {
    this.paused = !!p;
  }

  setMode(mode: HumanMode) {
    if (this.mode === mode) return;
    this.mode = mode;
    // Reseed waypoints so existing humans transition into the new mode immediately.
    for (const h of this.humans.values()) {
      h.mode = mode;
      h.waypoint = this.pickWaypoint(h);
      h.idleUntilMs = 0;
    }
  }

  /** Set the outer radius based on the current panel ring diameter. */
  setBounds(panelDiameter: number) {
    const panelRing = panelDiameter / 2;
    this.outerRadiusM = panelRing + 2.0;
    if (this.outerRadiusM <= this.innerRadiusM + 0.5) {
      this.outerRadiusM = this.innerRadiusM + 0.5;
    }
  }

  /** Advance the simulation by `dt` seconds. */
  tick(dt: number) {
    if (this.paused || dt <= 0) return;
    const now = Date.now();
    for (const h of this.humans.values()) {
      this.updateHuman(h, dt, now);
    }
    this.maintainPopulation();
  }

  private updateHuman(h: Human, dt: number, now: number) {
    h.prevPos.x = h.pos.x;
    h.prevPos.z = h.pos.z;

    if (h.idleUntilMs > now) {
      h.vel.x = 0;
      h.vel.z = 0;
      return;
    }

    const dx = h.waypoint.x - h.pos.x;
    const dz = h.waypoint.z - h.pos.z;
    const dist = Math.sqrt(dx * dx + dz * dz);

    if (dist <= WAYPOINT_REACHED_M) {
      h.pos.x = h.waypoint.x;
      h.pos.z = h.waypoint.z;
      h.vel.x = 0;
      h.vel.z = 0;
      this.onWaypointReached(h, now);
      return;
    }

    const stepLen = Math.min(dist, h.speed * this.speedMult * dt);
    const ux = dx / dist;
    const uz = dz / dist;
    h.pos.x += ux * stepLen;
    h.pos.z += uz * stepLen;
    h.vel.x = (h.pos.x - h.prevPos.x) / dt;
    h.vel.z = (h.pos.z - h.prevPos.z) / dt;

    const targetHeading = Math.atan2(ux, uz);
    h.heading = lerpAngle(h.heading, targetHeading, HEADING_LERP * dt);
  }

  private onWaypointReached(h: Human, now: number) {
    if (h.mode === "approach") {
      const insideZone = Math.hypot(h.pos.x, h.pos.z) <= this.innerRadiusM + 0.1;
      if (insideZone) {
        h.idleUntilMs = now + uniform(APPROACH_IDLE_MS_MIN, APPROACH_IDLE_MS_MAX);
        h.waypoint = this.randomPointOnRing(this.outerRadiusM + APPROACH_OUTER_PAD_M);
      } else {
        // Reached the outer ring → despawn; maintainPopulation will refill.
        this.humans.delete(h.id);
      }
    } else {
      h.idleUntilMs = now + uniform(IDLE_MS_MIN, IDLE_MS_MAX);
      h.waypoint = this.pickWaypoint(h);
    }
  }

  private maintainPopulation() {
    while (this.humans.size > this.targetCount) {
      // Remove the most recently spawned human first to avoid abrupt visible jumps.
      let lastId: string | null = null;
      let lastSpawn = -Infinity;
      for (const h of this.humans.values()) {
        if (h.spawnedAtMs > lastSpawn) {
          lastSpawn = h.spawnedAtMs;
          lastId = h.id;
        }
      }
      if (lastId) this.humans.delete(lastId);
      else break;
    }
    while (this.humans.size < this.targetCount) {
      this.spawnHuman();
    }
  }

  private spawnHuman() {
    const id = `human_${this.nextHumanIndex++}`;
    const now = Date.now();
    const speed = uniform(SPEED_MIN, SPEED_MAX);
    let pos: { x: number; z: number };
    let waypoint: { x: number; z: number };

    if (this.mode === "approach") {
      pos = this.randomPointOnRing(this.outerRadiusM + APPROACH_OUTER_PAD_M);
      waypoint = this.randomPointInDisk(0.5, this.innerRadiusM);
    } else {
      pos = this.randomPointInRing();
      waypoint = pos; // updated below
    }

    const h: Human = {
      id,
      pos,
      prevPos: { x: pos.x, z: pos.z },
      heading: Math.random() * Math.PI * 2 - Math.PI,
      speed,
      height: HUMAN_HEIGHT_M,
      color: colorForId(id),
      mode: this.mode,
      waypoint,
      idleUntilMs: 0,
      spawnedAtMs: now,
      vel: { x: 0, z: 0 },
    };
    if (this.mode !== "approach") h.waypoint = this.pickWaypoint(h);
    this.humans.set(id, h);
  }

  private pickWaypoint(h: Human): { x: number; z: number } {
    if (h.mode === "approach") {
      const insideZone = Math.hypot(h.pos.x, h.pos.z) <= this.innerRadiusM + 0.1;
      return insideZone
        ? this.randomPointOnRing(this.outerRadiusM + APPROACH_OUTER_PAD_M)
        : this.randomPointInDisk(0.5, this.innerRadiusM);
    }
    for (let i = 0; i < 8; i++) {
      const candidate = this.randomPointInRing();
      if (distance2D(candidate, h.pos) >= 2.0) return candidate;
    }
    return this.randomPointInRing();
  }

  private randomPointInRing(): { x: number; z: number } {
    const r = Math.sqrt(uniform(this.innerRadiusM ** 2, this.outerRadiusM ** 2));
    const a = Math.random() * Math.PI * 2;
    return { x: Math.sin(a) * r, z: Math.cos(a) * r };
  }

  private randomPointInDisk(rMin: number, rMax: number): { x: number; z: number } {
    const r = Math.sqrt(uniform(rMin * rMin, rMax * rMax));
    const a = Math.random() * Math.PI * 2;
    return { x: Math.sin(a) * r, z: Math.cos(a) * r };
  }

  private randomPointOnRing(radius: number): { x: number; z: number } {
    const a = Math.random() * Math.PI * 2;
    return { x: Math.sin(a) * radius, z: Math.cos(a) * radius };
  }
}

/**
 * Project a human into a sensor-local frame and decide whether the sensor
 * detects them. Sensor-local frame: X right, Y up, Z forward (along cone axis).
 *
 * Future-proof: this is the same math that will move into the Elixir
 * SensorMock. Returns null when the target is outside FoV or beyond range.
 */
export function projectToSensor(
  human: Human,
  pose: SensorPose,
  fov: SensorFov
): DetectedTarget | null {
  // Sensor's principal axes in world coordinates, derived from (yaw, tilt).
  // Cone axis = R_y(yaw) · R_x(-tilt) · (0, -1, 0) → the forward direction.
  const ct = Math.cos(pose.tiltRad);
  const st = Math.sin(pose.tiltRad);
  const cy = Math.cos(pose.yawRad);
  const sy = Math.sin(pose.yawRad);

  // forward = R_y(yaw) · (0, -cos(tilt), sin(tilt))
  const forward: [number, number, number] = [sy * st, -ct, cy * st];
  // right = R_y(yaw) · (1, 0, 0) (independent of tilt)
  const right: [number, number, number] = [cy, 0, -sy];
  // up = forward × right (right-handed)
  const up: [number, number, number] = [
    forward[1] * right[2] - forward[2] * right[1],
    forward[2] * right[0] - forward[0] * right[2],
    forward[0] * right[1] - forward[1] * right[0],
  ];

  // Target world position: human at (x, height/2, z) — torso center, roughly chest height.
  const tx = human.pos.x - pose.pos[0];
  const ty = human.height * 0.5 - pose.pos[1];
  const tz = human.pos.z - pose.pos[2];

  const localX = tx * right[0] + ty * right[1] + tz * right[2];
  const localY = tx * up[0] + ty * up[1] + tz * up[2];
  const localZ = tx * forward[0] + ty * forward[1] + tz * forward[2];

  const distance = Math.sqrt(localX * localX + localY * localY + localZ * localZ);
  if (distance > fov.rangeM || distance < 0.05) return null;
  if (localZ <= 0) return null;

  const azimuth = Math.atan2(localX, localZ);
  if (Math.abs(azimuth) > fov.hRad / 2) return null;

  const horiz = Math.sqrt(localX * localX + localZ * localZ);
  const elevation = Math.atan2(localY, horiz);
  if (Math.abs(elevation) > fov.vRad / 2) return null;

  // Radial velocity: sign convention positive = moving away from sensor.
  const dirX = tx / distance;
  const dirZ = tz / distance;
  const velocityRadial = human.vel.x * dirX + human.vel.z * dirZ;

  return {
    id: human.id,
    distance,
    azimuth,
    elevation,
    velocityRadial,
    posLocal: [localX, localY, localZ],
  };
}
