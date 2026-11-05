import { describe, it, expect, beforeEach } from "vitest";
import { handle, type Env, type Deps } from "../src/index";
import { validateUsage, dataPoint, queries, summary } from "../src/usage";
import { MemoryKV, fakeJira } from "./helpers";

class MemoryDataset {
  points: AnalyticsEngineDataPoint[] = [];
  writeDataPoint(point: AnalyticsEngineDataPoint) { this.points.push(point); }
}

let env: Env;
let kv: MemoryKV;
let usage: MemoryDataset;

beforeEach(() => {
  kv = new MemoryKV();
  usage = new MemoryDataset();
  env = {
    JIRA_BASE_URL: "https://lyre-app.atlassian.net", JIRA_PROJECT: "LYRE", REPORTS_PER_HOUR: "3",
    APP_ID: "28FC3LTQ82.com.pinkhatcreations.lyreapp", REQUIRE_ATTEST: "false",
    JIRA_EMAIL: "someone@example.com", JIRA_TOKEN: "secret", APP_KEY: "app-key", FILES_TOKEN: "files-token",
    REPORTS: kv as unknown as KVNamespace, USAGE: usage as unknown as AnalyticsEngineDataset, USAGE_PER_DAY: "2",
    CF_ACCOUNT_ID: "account", CF_API_TOKEN: "analytics-token",
  };
});

const deps: Deps = { fetch: fakeJira().fetch, now: () => new Date("2026-11-05T20:00:00Z") };

function event(overrides: Record<string, unknown> = {}) {
  return { name: "first_play", player: "liquid", source: "card", value: 6.2, date: "2026-11-05", day: 3,
           cohort: "2026-W44", version: "2.6.2", build: "11", device: "phone", os: "27", ...overrides };
}

function post(events: unknown[], headers: Record<string, string> = {}) {
  return new Request("https://relay.example/v1/usage", {
    method: "POST", headers: { "X-Lyre-Key": "app-key", "CF-Connecting-IP": "203.0.113.9", ...headers },
    body: JSON.stringify({ events }),
  });
}

describe("receiving usage statistics", () => {
  it("keeps each event in Analytics Engine, in the dashboard's columns", async () => {
    const response = await handle(post([event(), event({ name: "hang", screen: "Liquid: card deck", value: 781, source: undefined })]), env, deps);
    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ kept: 2 });
    expect(usage.points[0]).toEqual({
      indexes: ["first_play"],
      blobs: ["first_play", "liquid", "", "card", "", "2.6.2", "11", "phone", "27", "2026-W44", "2026-11-05"],
      doubles: [6.2, 3],
    });
    expect(usage.points[1].blobs?.[2]).toBe("Liquid: card deck");
  });

  it("drops events that aren't Lyre's kinds or carry free text, not the batch", () => {
    const checked = validateUsage({ events: [
      event(), event({ name: "keystroke" }), event({ detail: "Bohemian Rhapsody — Queen, live at Wembley 1986!!" }),
      event({ date: "yesterday" }), event({ value: "lots" }), event({ player: undefined }),
    ] });
    expect("events" in checked && checked.events.length).toBe(1);
    expect(validateUsage({})).toEqual({ error: "events missing" });
  });

  it("turns away a batch without the app's key", async () => {
    expect((await handle(post([event()], { "X-Lyre-Key": "wrong" }), env, deps)).status).toBe(401);
    expect(usage.points).toHaveLength(0);
  });

  it("takes a few batches a day from a sender, and never writes who sent them", async () => {
    expect((await handle(post([event()]), env, deps)).status).toBe(202);
    expect((await handle(post([event()]), env, deps)).status).toBe(202);
    expect((await handle(post([event()]), env, deps)).status).toBe(429);
    const written = JSON.stringify(usage.points);
    expect(written).not.toContain("203.0.113.9");
    expect([...kv.data.keys()].join()).not.toContain("203.0.113.9");
  });

  it("says when Analytics Engine isn't bound, so the app keeps its events", async () => {
    delete env.USAGE;
    expect((await handle(post([event()]), env, deps)).status).toBe(503);
  });
});

describe("the dashboard", () => {
  it("serves its page without a token, and its figures only with one", async () => {
    const page = await handle(new Request("https://relay.example/dashboard"), env, deps);
    expect(page.status).toBe(200);
    expect(page.headers.get("Content-Type")).toContain("text/html");
    expect(await page.text()).toContain("<title>Lyre Usage</title>");
    const denied = await handle(new Request("https://relay.example/v1/usage/summary"), env, deps);
    expect(denied.status).toBe(401);
  });

  it("asks Analytics Engine each question with the account's token", async () => {
    const asked: { url: string; sql: string; auth: string | null }[] = [];
    const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
      asked.push({ url: String(input), sql: String(init?.body), auth: new Headers(init?.headers).get("Authorization") });
      return new Response(JSON.stringify({ data: [{ name: "launch", n: 4 }] }), { status: 200 });
    }) as typeof fetch;
    const response = await handle(new Request("https://relay.example/v1/usage/summary?days=7", {
      headers: { Authorization: "Bearer files-token" } }), env, { ...deps, fetch: fetcher });
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body.totals).toEqual([{ name: "launch", n: 4 }]);
    expect(asked[0].url).toBe("https://api.cloudflare.com/client/v4/accounts/account/analytics_engine/sql");
    expect(asked[0].auth).toBe("Bearer analytics-token");
    expect(asked.every((a) => a.sql.includes("INTERVAL '7' DAY") && a.sql.endsWith("FORMAT JSON"))).toBe(true);
  });

  it("keeps a failed question to itself", async () => {
    const fetcher = (async (_: RequestInfo | URL, init?: RequestInit) =>
      String(init?.body).includes("'hang'") ? new Response("bad query", { status: 422 })
        : new Response(JSON.stringify({ data: [] }))) as typeof fetch;
    const result = await summary(30, "account", "token", fetcher);
    expect(result.hangs).toEqual({ error: "422: bad query" });
    expect(result.totals).toEqual([]);
  });

  it("clamps the range and never puts what's asked into the SQL", () => {
    expect(queries(1000).totals).toContain("INTERVAL '90' DAY");
    expect(queries(Number("7; DROP")).totals).toContain("INTERVAL '30' DAY");
    expect(dataPoint(event() as never).doubles).toEqual([6.2, 3]);
  });
});
