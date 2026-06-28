/**
 * HumanWorld — holds the people rendered in the 3D sim, fed exclusively by the
 * radar backend (`Octopus.Radar` PubSub `radar_frame` events).
 *
 * Coordinate system: A-Frame world frame. Y is up, ground is the X/Z plane.
 * Radar `x` → world X, radar `y` → world Z. Pose correction (mount offset +
 * rotation) happens server-side in `Octopus.Radar.Transform` before broadcast.
 */

/**
 * Externer Track aus dem Radar-Backend (`Octopus.Radar.Track`):
 *   x = links/rechts (m), y = vorne/hinten (m), z = Höhe (m),
 *   vx/vy/vz = Geschwindigkeit (m/s).
 * IDs sind uint32 vom Sensor; werden hier als Number rohweg übernommen.
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

export type Human = {
  id: string;
  pos: { x: number; z: number };
  prevPos: { x: number; z: number };
  heading: number;
  height: number;
  color: string;
  /** velocity vector in m/s (world frame, X/Z) */
  vel: { x: number; z: number };
};

const HUMAN_HEIGHT_M = 1.7;

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

export class HumanWorld {
  humans: Map<string, Human> = new Map();

  /**
   * Externe Tracks vom Radar-Backend einspeisen. Ersetzt die `humans`-Map
   * komplett bei jedem Frame — Tracks die in dieser Liste fehlen sind raus.
   * Heading wird aus dem Velocity-Vektor abgeleitet (sofern Bewegung > 5 cm/s,
   * sonst behält ein bekannter Track sein letztes Heading).
   *
   * Koordinaten-Mapping: Radar-`x` → Welt-X, Radar-`y` → Welt-Z.
   */
  setRadarTracks(tracks: RadarTrack[]) {
    const seen = new Set<string>();

    for (const t of tracks) {
      const id = `radar_${t.id}`;
      seen.add(id);
      const moving = Math.hypot(t.vx, t.vy) > 0.05;
      const existing = this.humans.get(id);
      const heading = moving ? Math.atan2(t.vx, t.vy) : existing?.heading ?? 0;

      if (existing) {
        existing.prevPos.x = existing.pos.x;
        existing.prevPos.z = existing.pos.z;
        existing.pos.x = t.x;
        existing.pos.z = t.y;
        existing.heading = heading;
        existing.vel.x = t.vx;
        existing.vel.z = t.vy;
      } else {
        this.humans.set(id, {
          id,
          pos: { x: t.x, z: t.y },
          prevPos: { x: t.x, z: t.y },
          heading,
          height: HUMAN_HEIGHT_M,
          color: colorForId(id),
          vel: { x: t.vx, z: t.vy },
        });
      }
    }

    for (const id of this.humans.keys()) {
      if (!seen.has(id)) this.humans.delete(id);
    }
  }
}
