// Lyre's usage statistics (the app's UsageStats.swift): small events, each a kind of thing
// and a number, never a name, kept in Workers Analytics Engine for the dashboard
// (dashboard.ts). Nothing here identifies a phone: no install ID comes with them, and
// the key that rate-limits a sender is never written with its events.

/** The events Lyre sends; anything else is dropped. */
export const EVENT_NAMES = [
  "install", "launch", "active", "screen", "bounce", "player_switch", "first_play", "play",
  "search", "hang", "error", "feature", "feature_first",
] as const;

export type EventName = typeof EVENT_NAMES[number];

export interface UsageEvent {
  name: EventName;
  player: string;
  screen?: string;
  source?: string;
  detail?: string;
  value?: number;
  date: string;
  day: number;
  cohort: string;
  version: string;
  build: string;
  device: string;
  os: string;
}

/** At most this many events in a batch (a day's, generously). */
export const MAX_EVENTS = 5000;
export const MAX_USAGE_BYTES = 2_000_000;

// A field's words: a kind ("Liquid: card deck", "songsShelf", "2.6.1"), never free text.
const WORD = /^[A-Za-z0-9 :._+-]{0,48}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const COHORT = /^\d{4}-W\d{2}$/;

function word(value: unknown, required = false): string | undefined | null {
  if (value === undefined || value === null) return required ? null : undefined;
  return typeof value === "string" && WORD.test(value) ? value : null;
}

/** The batch's events that are well formed; a malformed one is dropped, not the batch. */
export function validateUsage(body: unknown): { events: UsageEvent[] } | { error: string } {
  const list = (body as { events?: unknown })?.events;
  if (!Array.isArray(list)) return { error: "events missing" };
  if (list.length > MAX_EVENTS) return { error: "too many events" };
  const events: UsageEvent[] = [];
  for (const raw of list) {
    const e = raw as Record<string, unknown>;
    if (!EVENT_NAMES.includes(e?.name as EventName)) continue;
    const fields = {
      player: word(e.player, true), screen: word(e.screen), source: word(e.source), detail: word(e.detail),
      version: word(e.version, true), build: word(e.build, true), device: word(e.device, true), os: word(e.os, true),
    };
    if (Object.values(fields).some((v) => v === null)) continue;
    if (typeof e.date !== "string" || !DATE.test(e.date) || typeof e.cohort !== "string" || !COHORT.test(e.cohort)) continue;
    if (typeof e.day !== "number" || !Number.isInteger(e.day) || e.day < 0 || e.day > 100_000) continue;
    if (e.value !== undefined && (typeof e.value !== "number" || !Number.isFinite(e.value))) continue;
    events.push({
      name: e.name as EventName, date: e.date, cohort: e.cohort, day: e.day, value: e.value as number | undefined,
      ...(fields as Omit<UsageEvent, "name" | "date" | "cohort" | "day" | "value">),
    });
  }
  return { events };
}

/** An event as Analytics Engine keeps it. Its columns (the dashboard's queries name them):
 *  blob1 name · blob2 player · blob3 screen · blob4 source · blob5 detail · blob6 version ·
 *  blob7 build · blob8 device · blob9 os · blob10 cohort · blob11 date;
 *  double1 value · double2 days since install. */
export function dataPoint(e: UsageEvent): AnalyticsEngineDataPoint {
  return {
    indexes: [e.name],
    blobs: [e.name, e.player, e.screen ?? "", e.source ?? "", e.detail ?? "", e.version, e.build,
            e.device, e.os, e.cohort, e.date],
    doubles: [e.value ?? 0, e.day],
  };
}

// MARK: The Dashboard's Questions

export const DATASET = "lyre_usage";

/** Each question the dashboard asks, over the last `days` days, as Analytics Engine SQL.
 *  Counts are sums of _sample_interval, so they stay right if Analytics Engine samples. */
export function queries(days: number): Record<string, string> {
  const n = Number.isFinite(days) ? Math.max(1, Math.min(90, Math.floor(days))) : 30;
  const since = `timestamp > NOW() - INTERVAL '${n}' DAY`;
  const count = "SUM(_sample_interval)";
  const mean = "SUM(_sample_interval * double1) / SUM(_sample_interval)";
  const of = (name: string) => `FROM ${DATASET} WHERE blob1 = '${name}' AND ${since}`;
  return {
    totals: `SELECT blob1 AS name, ${count} AS n FROM ${DATASET} WHERE ${since} GROUP BY name`,
    activeByDay: `SELECT blob11 AS date, blob2 AS player, ${count} AS n ${of("active")} GROUP BY date, player ORDER BY date`,
    switches: `SELECT blob5 AS from_player, blob2 AS to_player, ${count} AS n, ${mean} AS seconds ${of("player_switch")} GROUP BY from_player, to_player ORDER BY n DESC`,
    returning: `SELECT blob10 AS cohort, double2 AS day, ${count} AS n ${of("launch")} GROUP BY cohort, day ORDER BY cohort, day`,
    installs: `SELECT blob10 AS cohort, ${count} AS n ${of("install")} GROUP BY cohort ORDER BY cohort`,
    firstPlay: `SELECT blob4 AS source, blob2 AS player, ${count} AS n, ${mean} AS seconds ${of("first_play")} GROUP BY source, player ORDER BY n DESC`,
    playSources: `SELECT blob4 AS source, ${count} AS n ${of("play")} GROUP BY source ORDER BY n DESC`,
    screens: `SELECT blob3 AS screen, ${count} AS n ${of("screen")} GROUP BY screen ORDER BY n DESC`,
    bounces: `SELECT blob3 AS screen, ${count} AS n, ${mean} AS seconds ${of("bounce")} GROUP BY screen ORDER BY n DESC`,
    searches: `SELECT blob2 AS player, blob5 AS result, ${count} AS n ${of("search")} GROUP BY player, result`,
    hangs: `SELECT blob3 AS screen, blob2 AS player, ${count} AS n, ${mean} AS ms ${of("hang")} GROUP BY screen, player ORDER BY n DESC`,
    errors: `SELECT blob5 AS kind, ${count} AS n ${of("error")} GROUP BY kind ORDER BY n DESC`,
    featuresFound: `SELECT blob5 AS feature, ${count} AS n ${of("feature_first")} GROUP BY feature ORDER BY n DESC`,
    featureUse: `SELECT blob5 AS feature, blob2 AS player, ${count} AS n ${of("feature")} GROUP BY feature, player ORDER BY n DESC`,
    versions: `SELECT blob6 AS version, blob7 AS build, ${count} AS n ${of("launch")} GROUP BY version, build ORDER BY version DESC, build DESC`,
  };
}

/** Asks Analytics Engine's SQL API each question; a question that fails says so alone. */
export async function summary(days: number, accountID: string, token: string, fetcher: typeof fetch):
  Promise<Record<string, unknown[] | { error: string }>> {
  const entries = await Promise.all(Object.entries(queries(days)).map(async ([key, sql]) => {
    try {
      const response = await fetcher(`https://api.cloudflare.com/client/v4/accounts/${accountID}/analytics_engine/sql`, {
        method: "POST", headers: { Authorization: `Bearer ${token}` }, body: `${sql} FORMAT JSON`,
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) return [key, { error: `${response.status}: ${(await response.text()).slice(0, 200)}` }] as const;
      const result = await response.json() as { data?: unknown[] };
      return [key, result.data ?? []] as const;
    } catch (error) {
      return [key, { error: String(error) }] as const;
    }
  }));
  return Object.fromEntries(entries);
}
