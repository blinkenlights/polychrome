/**
 * HumanWorld — people rendered in the 3D sim.
 *
 * Detected humans come from radar `radar_frame` events, one avatar per
 * `{device_id, track_id}` pair — same rule as `OctopusWeb.RadarLive`.
 *
 * Mock-world ground truth is intentionally not rendered here so the 3D view
 * stays aligned with the radar page (detections only).
 *
 * Coordinate system: A-Frame world frame. Y is up, ground is the X/Z plane.
 * Installation global radar `(x, y)` maps to A-Frame `(X, Z)` via
 * `radarGlobalToAframeXZ/2` so detections line up with the 2D radar SVG.
 * Pose correction (mount offset + rotation) happens server-side in
 * `Octopus.Radar.Transform` before broadcast.
 */

/** Installation global meters (radar `x`/`y`) → A-Frame ground `X`/`Z`. */
export function radarGlobalToAframeXZ(
  radarX: number,
  radarY: number,
): { x: number; z: number } {
  return { x: -radarX, z: radarY };
}

/**
 * Externer Track aus dem Radar-Backend (`Octopus.Radar.Track`):
 *   x = links/rechts (m), y = vorne/hinten (m), z = Höhe (m),
 *   vx/vy/vz = Geschwindigkeit (m/s).
 */
export type RadarTrack = {
  id: number;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
};

type MergedRadarTrack = RadarTrack & {
  deviceId: number;
  compositeId: number;
};

/** Same composite id rule as `Octopus.Apps.Collective.track_to_person/2`. */
export function compositeTrackId(deviceId: number, trackId: number): number {
  return deviceId * 10_000 + trackId;
}

/** Ground-truth person from the mock world feed. */
export type MockWorldObject = {
  id: number;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
};

export type Human = {
  id: string;
  pos: { x: number; z: number };
  prevPos: { x: number; z: number };
  heading: number;
  height: number;
  color: string;
  ghost: boolean;
  /** velocity vector in m/s (world frame, X/Z) */
  vel: { x: number; z: number };
};

const HUMAN_HEIGHT_M = 1.7;

function nowMs(): number {
  return typeof performance !== "undefined" && performance.now
    ? performance.now()
    : Date.now();
}

function hashStringToUnit(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 1000000) / 1000000;
}

export function colorForId(id: string): string {
  const h = Math.floor(hashStringToUnit(id) * 360);
  return `hsl(${h}, 55%, 55%)`;
}

const DEVICE_TTL_MS = 1000;

export class HumanWorld {
  humans: Map<string, Human> = new Map();
  ghosts: Map<string, Human> = new Map();

  private deviceTracks: Map<number, { tracks: RadarTrack[]; ts: number }> =
    new Map();

  private mockObjects: MockWorldObject[] = [];

  setRadarTracksForDevice(deviceId: number, tracks: RadarTrack[]) {
    this.deviceTracks.set(deviceId, { tracks, ts: nowMs() });
    this.rebuild();
  }

  setMockWorldObjects(objects: MockWorldObject[]) {
    this.mockObjects = objects;
    this.rebuildGhosts();
  }

  clearMockWorld() {
    this.mockObjects = [];
    this.ghosts.clear();
  }

  private rebuild() {
    const now = nowMs();
    const merged = new Map<number, MergedRadarTrack>();

    for (const [deviceId, entry] of this.deviceTracks) {
      if (now - entry.ts > DEVICE_TTL_MS) {
        this.deviceTracks.delete(deviceId);
        continue;
      }
      for (const t of entry.tracks) {
        const compositeId = compositeTrackId(deviceId, t.id);
        merged.set(compositeId, { ...t, deviceId, compositeId });
      }
    }

    this.applyTracks([...merged.values()]);
    this.rebuildGhosts();
  }

  private applyTracks(tracks: MergedRadarTrack[]) {
    const seen = new Set<string>();

    for (const t of tracks) {
      const id = `radar_${t.compositeId}`;
      seen.add(id);
      const { x, z } = radarGlobalToAframeXZ(t.x, t.y);
      const moving = Math.hypot(t.vx, t.vy) > 0.05;
      const existing = this.humans.get(id);
      const heading = moving ? Math.atan2(-t.vx, t.vy) : existing?.heading ?? 0;

      if (existing) {
        existing.prevPos.x = existing.pos.x;
        existing.prevPos.z = existing.pos.z;
        existing.pos.x = x;
        existing.pos.z = z;
        existing.heading = heading;
        existing.vel.x = -t.vx;
        existing.vel.z = t.vy;
      } else {
        this.humans.set(id, {
          id,
          pos: { x, z },
          prevPos: { x, z },
          heading,
          height: HUMAN_HEIGHT_M,
          color: colorForId(id),
          ghost: false,
          vel: { x: -t.vx, z: t.vy },
        });
      }
    }

    for (const id of this.humans.keys()) {
      if (!seen.has(id)) this.humans.delete(id);
    }
  }

  private rebuildGhosts() {
    this.ghosts.clear();
  }
}
