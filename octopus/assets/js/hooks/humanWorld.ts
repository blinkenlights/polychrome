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

/** Monotone Zeit in ms; fällt auf Date.now zurück, falls performance fehlt. */
function nowMs(): number {
  return typeof performance !== "undefined" && performance.now
    ? performance.now()
    : Date.now();
}

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

/**
 * Wie lange die letzten Tracks eines Sensors gültig bleiben, wenn keine neuen
 * Frames mehr kommen (z.B. Sensor deaktiviert). Bei 10 Hz pro Sensor ist 1 s
 * großzügig; danach fällt der Sensor aus der Union.
 */
const DEVICE_TTL_MS = 1000;

export class HumanWorld {
  humans: Map<string, Human> = new Map();

  /**
   * Letzter Frame je Sensor (device_id → Tracks + Zeitstempel). Jeder Sensor
   * sieht nur eine Teilmenge der Personen (Reichweite/Position), daher wird die
   * gerenderte Welt aus der *Union* aller frischen Sensor-Frames gebildet statt
   * bei jedem einzelnen Frame komplett überschrieben.
   */
  private deviceTracks: Map<number, { tracks: RadarTrack[]; ts: number }> =
    new Map();

  /**
   * Frame eines einzelnen Sensors einspeisen. Ersetzt nur die Tracks *dieses*
   * Sensors und baut danach die gemergte Welt neu auf. So flackern Personen
   * nicht mehr, wenn mehrere Sensoren (mit unterschiedlichen Teilansichten)
   * interleaved senden.
   */
  setRadarTracksForDevice(deviceId: number, tracks: RadarTrack[]) {
    this.deviceTracks.set(deviceId, { tracks, ts: nowMs() });
    this.rebuild();
  }

  /**
   * Union aller frischen Sensor-Frames bilden (dedupe per Track-ID; bei
   * Kollision gewinnt der zuletzt einspeiste Sensor) und anwenden. Sensoren,
   * deren letzter Frame älter als `DEVICE_TTL_MS` ist, fallen raus.
   */
  private rebuild() {
    const now = nowMs();
    const merged = new Map<number, RadarTrack>();

    for (const [deviceId, entry] of this.deviceTracks) {
      if (now - entry.ts > DEVICE_TTL_MS) {
        this.deviceTracks.delete(deviceId);
        continue;
      }
      for (const t of entry.tracks) merged.set(t.id, t);
    }

    this.applyTracks([...merged.values()]);
  }

  /**
   * Gemergte Track-Liste auf die `humans`-Map anwenden — Tracks die fehlen sind
   * raus. Heading wird aus dem Velocity-Vektor abgeleitet (sofern Bewegung
   * > 5 cm/s, sonst behält ein bekannter Track sein letztes Heading).
   *
   * Koordinaten-Mapping: Radar-`x` → Welt-X, Radar-`y` → Welt-Z.
   */
  private applyTracks(tracks: RadarTrack[]) {
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
