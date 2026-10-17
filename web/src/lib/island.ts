// The recording indicator's geometry for the home page's hero, from DynamicLanding's
// `IslandGeometry` with JustScribe's configuration, on a 185 × 32 pt notch centred at x = 340.

export interface Pose {
  w: number;
  h: number;
  top: number;
  bottom: number;
  /** How much of the compact content (waveform, timer) shows. */
  compact: number;
  /** How much of the expanded card shows. */
  expanded: number;
}

/** Hidden is the notch with its own tight corners; compact fits the 18 pt waveform and the
 *  ~26 pt timer beside the notch; expanded holds the 220 × 40 card under it. */
export const poses = {
  hidden: { w: 185, h: 32, top: 4, bottom: 8, compact: 0, expanded: 0 },
  compact: { w: 299, h: 32, top: 15, bottom: 20, compact: 1, expanded: 0 },
  expanded: { w: 282, h: 94, top: 15, bottom: 20, compact: 0, expanded: 1 },
} satisfies Record<string, Pose>;

const centre = 340;

/** `IslandShape.path`: flared top corners, rounded bottom ones. */
export function islandPath({ w, h, top, bottom }: Pose): string {
  const x0 = centre - w / 2, x1 = centre + w / 2;
  const t = Math.min(top, w / 4, h / 2);
  const b = Math.min(bottom, (w - 2 * t) / 2, Math.max(0, h - t));
  return `M${x0} 0Q${x0 + t} 0 ${x0 + t} ${t}L${x0 + t} ${h - b}Q${x0 + t} ${h} ${x0 + t + b} ${h}` +
    `L${x1 - t - b} ${h}Q${x1 - t} ${h} ${x1 - t} ${h - b}L${x1 - t} ${t}Q${x1 - t} 0 ${x1} 0Z`;
}

/** A bar's scale for a level 0…1: `IslandWaveformView` draws 3 + 11 × level of 14 pt. */
export const barScale = (level: number) => (3 + level * 11) / 14;

/** The listening frame shown without animation. */
export const stillBars = [0.35, 0.7, 1, 0.7, 0.35];
