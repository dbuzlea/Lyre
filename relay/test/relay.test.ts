import { describe, it, expect, beforeEach } from "vitest";
import { handle, signature, type Env, type Deps } from "../src/index";
import { fingerprint, priority, labels, validate, type Report } from "../src/report";

// Fakes for the Worker's world: KV and R2 in memory, and a Jira that records what it's
// asked and answers like Jira Cloud.

class MemoryKV {
  data = new Map<string, string>();
  async get(key: string, type?: string) {
    const value = this.data.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) : value;
  }
  async put(key: string, value: string) { this.data.set(key, value); }
}

class MemoryR2 {
  data = new Map<string, { bytes: Uint8Array; contentType?: string }>();
  async put(key: string, bytes: Uint8Array, options?: { httpMetadata?: { contentType?: string } }) {
    this.data.set(key, { bytes, contentType: options?.httpMetadata?.contentType });
  }
  async get(key: string) {
    const item = this.data.get(key);
    return item ? { body: item.bytes, httpMetadata: { contentType: item.contentType } } : null;
  }
}

interface Call { url: string; body: any; auth: string | null }

function fakeJira(options: { rejectPriority?: boolean } = {}) {
  const calls: Call[] = [];
  let next = 100;
  const fakeFetch: typeof fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url.endsWith("/attachments")) {
      const form = init?.body as FormData;
      calls.push({ url, body: { files: form.getAll("file").map((f) => (f as File).name) },
                   auth: new Headers(init?.headers).get("X-Atlassian-Token") });
      return new Response("[]", { status: 200 });
    }
    const body = JSON.parse(String(init?.body));
    calls.push({ url, body, auth: new Headers(init?.headers).get("Authorization") });
    if (url.endsWith("/rest/api/3/issue")) {
      if (options.rejectPriority && body.fields.priority) return new Response("{}", { status: 400 });
      return new Response(JSON.stringify({ key: `LYRE-${next++}` }), { status: 201 });
    }
    if (url.endsWith("/comment")) return new Response("{}", { status: 201 });
    return new Response("{}", { status: 404 });
  }) as typeof fetch;
  return { calls, fetch: fakeFetch };
}

const installID = "8B0F3C2E-1D4A-4E6B-9C7D-2A5F8E1B3C4D";

function report(overrides: Partial<Report> = {}): Report {
  return {
    kind: "metrickit",
    title: "Crash",
    signature: "EXC_BAD_ACCESS",
    stack: "0 Lyre 0x1000 MusicService.play + 120\n1 Lyre 0x2000 SpoolPlayerView.insertTape + 44",
    app: { version: "2.6.1", build: "9", binaryUUID: "1EC58826-BDF2-3A0E-986A-DB3BCB21C06D", player: "liquid" },
    device: { model: "iPhone18,4", os: "iOS 27.0.1" },
    installID,
    logTail: "2026-11-04T19:41:11 [notice] [app] Launched",
    ...overrides,
  };
}

let env: Env;
let kv: MemoryKV;
let r2: MemoryR2;

beforeEach(() => {
  kv = new MemoryKV();
  r2 = new MemoryR2();
  env = {
    JIRA_BASE_URL: "https://lyre-app.atlassian.net", JIRA_PROJECT: "LYRE", REPORTS_PER_HOUR: "3",
    JIRA_EMAIL: "someone@example.com", JIRA_TOKEN: "secret", APP_KEY: "app-key", FILES_TOKEN: "files-token",
    REPORTS: kv as unknown as KVNamespace, FILES: r2 as unknown as R2Bucket,
  };
});

function post(body: unknown, key = "app-key") {
  return new Request("https://relay.example/v1/reports", {
    method: "POST", headers: { "X-Lyre-Key": key, "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
}

const deps = (jira: ReturnType<typeof fakeJira>): Deps => ({ fetch: jira.fetch, now: () => new Date("2026-11-04T20:00:00Z") });

describe("receiving a report", () => {
  it("files a new problem as a Bug in LYRE, labelled for triage but never claude", async () => {
    const jira = fakeJira();
    const response = await handle(post(report()), env, deps(jira));
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({ issue: "LYRE-100", repeat: false });
    const fields = jira.calls[0].body.fields;
    expect(jira.calls[0].url).toBe("https://lyre-app.atlassian.net/rest/api/3/issue");
    expect(fields.project).toEqual({ key: "LYRE" });
    expect(fields.issuetype).toEqual({ name: "Bug" });
    expect(fields.summary).toBe("[Auto] Crash (2.6.1 build 9)");
    expect(fields.labels).toEqual(["auto-report", "needs-triage", "report-metrickit"]);
    expect(fields.labels).not.toContain("claude");
    expect(fields.priority).toEqual({ name: "High" });
    expect(jira.calls[0].auth).toBe(`Basic ${btoa("someone@example.com:secret")}`);
  });

  it("puts the evidence in the issue's text: build, device, stack and log", async () => {
    const jira = fakeJira();
    await handle(post(report()), env, deps(jira));
    const text = JSON.stringify(jira.calls[0].body.fields.description);
    expect(text).toContain("1EC58826-BDF2-3A0E-986A-DB3BCB21C06D");
    expect(text).toContain("iPhone18,4");
    expect(text).toContain("MusicService.play");
    expect(text).toContain("[app] Launched");
  });

  it("notes a repeat on the issue it first became, instead of filing another", async () => {
    const jira = fakeJira();
    await handle(post(report()), env, deps(jira));
    // Another launch: different addresses, same problem.
    const again = report({ stack: "0 Lyre 0x9999 MusicService.play + 120\n1 Lyre 0x8888 SpoolPlayerView.insertTape + 44" });
    const response = await handle(post(again), env, deps(jira));
    expect(await response.json()).toEqual({ issue: "LYRE-100", repeat: true, count: 2 });
    expect(jira.calls).toHaveLength(2);
    expect(jira.calls[1].url).toBe("https://lyre-app.atlassian.net/rest/api/3/issue/LYRE-100/comment");
    expect(JSON.stringify(jira.calls[1].body)).toContain("2 times so far");
  });

  it("files every listener's own report separately", async () => {
    const jira = fakeJira();
    const userReport = report({ kind: "user", title: "Covers missing", description: "No artwork anywhere", stack: undefined });
    await handle(post(userReport), env, deps(jira));
    await handle(post(userReport), env, deps(jira));
    expect(jira.calls.map((c) => c.url.endsWith("/issue"))).toEqual([true, true]);
    expect(jira.calls[0].body.fields.summary).toBe("[Reported] Covers missing (2.6.1 build 9)");
    expect(JSON.stringify(jira.calls[0].body.fields.description)).toContain("No artwork anywhere");
  });

  it("keeps the report's files in R2 and links each from the issue with its own signature", async () => {
    const jira = fakeJira();
    const withFile = report({ files: [{ name: "lyre.log", contentType: "text/plain", base64: btoa("log lines") }] });
    await handle(post(withFile), env, deps(jira));
    const [key] = [...r2.data.keys()];
    expect(key).toMatch(/\/lyre\.log$/);
    expect(new TextDecoder().decode(r2.data.get(key)!.bytes)).toBe("log lines");
    const sig = await signature(key, "files-token");
    const text = JSON.stringify(jira.calls[0].body.fields.description);
    expect(text).toContain(`https://relay.example/v1/files/${key}?sig=${sig}`);
    expect(text).not.toContain("files-token");
  });

  it("attaches the report's files to the new issue, to see in Jira", async () => {
    const jira = fakeJira();
    const withShot = report({ kind: "user", title: "Look", stack: undefined,
                              files: [{ name: "screenshot.jpg", contentType: "image/jpeg", base64: btoa("jpeg") }] });
    await handle(post(withShot), env, deps(jira));
    const attachment = jira.calls.find((c) => c.url.endsWith("/rest/api/3/issue/LYRE-100/attachments"));
    expect(attachment?.body.files).toEqual(["screenshot.jpg"]);
    expect(attachment?.auth).toBe("no-check");
  });

  it("files it without a priority when the project won't take one", async () => {
    const jira = fakeJira({ rejectPriority: true });
    const response = await handle(post(report()), env, deps(jira));
    expect(response.status).toBe(201);
    expect(jira.calls).toHaveLength(2);
    expect(jira.calls[1].body.fields.priority).toBeUndefined();
  });
});

describe("without R2", () => {
  it("still files the report, without its files", async () => {
    const jira = fakeJira();
    const { FILES: _unused, ...withoutFiles } = env;
    const withFile = report({ files: [{ name: "lyre.log", contentType: "text/plain", base64: btoa("log lines") }] });
    const response = await handle(post(withFile), withoutFiles as Env, deps(jira));
    expect(response.status).toBe(201);
    expect(JSON.stringify(jira.calls[0].body.fields.description)).not.toContain("/v1/files/");
  });
});

describe("when Jira is out of reach", () => {
  it("tells the app to try later instead of crashing", async () => {
    const unreachable: Deps = { fetch: (async () => { throw new TypeError("connect ECONNREFUSED"); }) as typeof fetch,
                                now: () => new Date("2026-11-04T20:00:00Z") };
    const response = await handle(post(report()), env, unreachable);
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "jira create failed", status: 503 });
  });
});

describe("turning reports away", () => {
  it("without the app's key", async () => {
    const jira = fakeJira();
    expect((await handle(post(report(), "wrong"), env, deps(jira))).status).toBe(401);
    expect(jira.calls).toHaveLength(0);
  });

  it("past a phone's share for the hour", async () => {
    const jira = fakeJira();
    const statuses = [];
    for (let i = 0; i < 4; i++) {
      statuses.push((await handle(post(report({ signature: `s${i}` })), env, deps(jira))).status);
    }
    expect(statuses).toEqual([201, 201, 201, 429]);
  });

  it("that aren't reports", async () => {
    const jira = fakeJira();
    expect((await handle(post({ kind: "nope" }), env, deps(jira))).status).toBe(400);
    expect(validate({ ...report(), installID: "not-a-uuid" })).toEqual({ error: "bad installID" });
  });
});

describe("reading a file back", () => {
  it("with its own signature, which opens no other file", async () => {
    await r2.put("abc/shot.jpg", new TextEncoder().encode("jpeg"), { httpMetadata: { contentType: "image/jpeg" } });
    await r2.put("xyz/other.log", new TextEncoder().encode("other"));
    const jira = fakeJira();
    const sig = await signature("abc/shot.jpg", "files-token");
    const own = await handle(new Request(`https://relay.example/v1/files/abc/shot.jpg?sig=${sig}`), env, deps(jira));
    expect(own.status).toBe(200);
    expect(own.headers.get("Content-Type")).toBe("image/jpeg");
    const other = await handle(new Request(`https://relay.example/v1/files/xyz/other.log?sig=${sig}`), env, deps(jira));
    expect(other.status).toBe(401);
  });

  it("or with the files token", async () => {
    await r2.put("abc/lyre.log", new TextEncoder().encode("hello"), { httpMetadata: { contentType: "text/plain" } });
    const jira = fakeJira();
    const denied = await handle(new Request("https://relay.example/v1/files/abc/lyre.log"), env, deps(jira));
    expect(denied.status).toBe(401);
    const allowed = await handle(new Request("https://relay.example/v1/files/abc/lyre.log?token=files-token"), env, deps(jira));
    expect(await allowed.text()).toBe("hello");
  });
});

describe("the rules", () => {
  it("a crash is High; a listener's report Medium", () => {
    expect(priority(report())).toBe("High");
    expect(priority(report({ kind: "user", title: "Something odd" }))).toBe("Medium");
  });
  it("the same problem in another version is a new issue", async () => {
    expect(await fingerprint(report())).not.toBe(await fingerprint(report({ app: { version: "2.6.2", build: "1" } })));
  });
  it("never labels it claude", () => {
    expect(labels(report({ kind: "user" }))).not.toContain("claude");
  });
});
