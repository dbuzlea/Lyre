import "reflect-metadata";
import { describe, it, expect, beforeEach } from "vitest";
import { syncTestFlight, handle, type Env, type Deps } from "../src/index";
import { ascToken } from "../src/testflight";
import { bytesToBase64 } from "../src/attest";
import { MemoryKV, MemoryR2 } from "./helpers";

// A stand-in App Store Connect: the app's feedback and crash submissions, a crash log,
// and screenshot images; and a Jira that records what it's asked.

const now = new Date("2026-11-06T12:00:00Z");

async function apiKey() {
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey) as ArrayBuffer);
  const pem = `-----BEGIN PRIVATE KEY-----\n${bytesToBase64(pkcs8).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----`;
  return { keys, pem };
}

function world(options: { feedback?: any[]; crashes?: any[] } = {}) {
  const calls: { url: string; body?: any; auth?: string | null }[] = [];
  let next = 200;
  const feedback = options.feedback ?? [{
    id: "fb-1", type: "betaFeedbackScreenshotSubmissions",
    attributes: { comment: "The shelf jumps when I scroll\nevery time", email: "tester@example.com", deviceModel: "iPhone18,4",
                  osVersion: "27.0.1", createdDate: "2026-11-06T10:00:00Z",
                  screenshots: [{ url: "https://images.example/shot-1.jpg", width: 1206, height: 2622 }] },
    relationships: { build: { data: { type: "builds", id: "b-9" } } },
  }];
  const crashes = options.crashes ?? [{
    id: "cr-1", type: "betaFeedbackCrashSubmissions",
    attributes: { comment: "It closed", email: "tester@example.com", deviceModel: "iPhone17,1", osVersion: "27.0", createdDate: "2026-11-06T11:00:00Z" },
    relationships: { build: { data: { type: "builds", id: "b-9" } } },
  }];
  const included = [{ type: "builds", id: "b-9", attributes: { version: "9" } }];
  const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const auth = new Headers(init?.headers).get("Authorization");
    if (url.includes("/betaFeedbackScreenshotSubmissions?")) { calls.push({ url, auth }); return Response.json({ data: feedback, included }); }
    if (url.includes("/betaFeedbackCrashSubmissions?")) { calls.push({ url, auth }); return Response.json({ data: crashes, included }); }
    if (url.endsWith("/crashLog")) { calls.push({ url, auth }); return Response.json({ data: { attributes: { logText: "Exception Type: EXC_CRASH (SIGABRT)\nThread 0 Crashed" } } }); }
    if (url.startsWith("https://images.example/")) { calls.push({ url }); return new Response(new Uint8Array([0xff, 0xd8, 0xff]), { headers: { "Content-Type": "image/jpeg" } }); }
    if (url.endsWith("/rest/api/3/issue")) { const body = JSON.parse(String(init?.body)); calls.push({ url, body }); return Response.json({ key: `LYRE-${next++}` }, { status: 201 }); }
    if (url.endsWith("/attachments")) { calls.push({ url, body: { files: (init?.body as FormData).getAll("file").map((f) => (f as File).name) } }); return Response.json([]); }
    return new Response("{}", { status: 404 });
  }) as typeof fetch;
  return { calls, deps: { fetch: fetcher, now: () => now } as Deps };
}

let env: Env;

beforeEach(async () => {
  const { pem } = await apiKey();
  env = {
    JIRA_BASE_URL: "https://lyre-app.atlassian.net", JIRA_PROJECT: "LYRE", REPORTS_PER_HOUR: "10",
    APP_ID: "28FC3LTQ82.com.pinkhatcreations.lyreapp", REQUIRE_ATTEST: "false",
    JIRA_EMAIL: "someone@example.com", JIRA_TOKEN: "secret", APP_KEY: "app-key", FILES_TOKEN: "files-token",
    REPORTS: new MemoryKV() as unknown as KVNamespace, FILES: new MemoryR2() as unknown as R2Bucket,
    ASC_KEY_ID: "KEY123", ASC_ISSUER_ID: "issuer-uuid", ASC_PRIVATE_KEY: pem, ASC_APP_ID: "6741000000",
    TESTFLIGHT_SINCE: "2026-11-05T00:00:00Z", RELAY_URL: "https://relay.example",
  };
});

describe("App Store Connect's token", () => {
  it("is an ES256 JWT for the API key, good for 20 minutes, that verifies", async () => {
    const { keys, pem } = await apiKey();
    const token = await ascToken("KEY123", "issuer-uuid", pem, now);
    const [header, payload, signature] = token.split(".");
    const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    expect(decode(header)).toEqual({ alg: "ES256", kid: "KEY123", typ: "JWT" });
    expect(decode(payload)).toEqual({ iss: "issuer-uuid", iat: now.getTime() / 1000, exp: now.getTime() / 1000 + 1200, aud: "appstoreconnect-v1" });
    const raw = Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, keys.publicKey, raw,
                                      new TextEncoder().encode(`${header}.${payload}`))).toBe(true);
  });
});

describe("the bridge", () => {
  it("files feedback and crashes, oldest first, with the tester's words, build, screenshot and crash log", async () => {
    const { calls, deps } = world();
    expect(await syncTestFlight(env, deps)).toEqual({ filed: ["LYRE-200", "LYRE-201"] });
    const issues = calls.filter((c) => c.url.endsWith("/rest/api/3/issue"));
    expect(issues.map((c) => c.body.fields.summary)).toEqual([
      "[TestFlight] Feedback: The shelf jumps when I scroll (build 9)",
      "[TestFlight] Crash: It closed (build 9)",
    ]);
    expect(issues[0].body.fields.labels).toEqual(["auto-report", "needs-triage", "report-testflight"]);
    const feedback = JSON.stringify(issues[0].body.fields.description);
    expect(feedback).toContain("tester@example.com");
    expect(feedback).toContain("https://relay.example/v1/files/testflight-fb-1/screenshot-1.jpg?sig=");
    expect(JSON.stringify(issues[1].body.fields.description)).toContain("EXC_CRASH (SIGABRT)");
    const attachments = calls.filter((c) => c.url.endsWith("/attachments")).map((c) => c.body.files);
    expect(attachments).toEqual([["screenshot-1.jpg"], ["crash.ips"]]);
    expect(calls.find((c) => c.url.includes("betaFeedbackScreenshotSubmissions"))?.auth).toMatch(/^Bearer /);
  });

  it("doesn't file a submission twice", async () => {
    const { calls, deps } = world();
    await syncTestFlight(env, deps);
    expect(await syncTestFlight(env, deps)).toEqual({ filed: [] });
    expect(calls.filter((c) => c.url.endsWith("/rest/api/3/issue"))).toHaveLength(2);
  });

  it("leaves what came before it was turned on", async () => {
    const old = [{ id: "fb-old", attributes: { comment: "Old", createdDate: "2026-10-01T00:00:00Z", screenshots: [] } }];
    const { deps } = world({ feedback: old, crashes: [] });
    expect(await syncTestFlight(env, deps)).toEqual({ filed: [] });
  });

  it("does nothing without an App Store Connect key", async () => {
    const { calls, deps } = world();
    delete env.ASC_KEY_ID;
    expect(await syncTestFlight(env, deps)).toEqual({ filed: [], skipped: "no App Store Connect key" });
    expect(calls).toHaveLength(0);
  });

  it("runs on request only with the files token", async () => {
    const { deps } = world();
    expect((await handle(new Request("https://relay.example/v1/testflight/sync", { method: "POST" }), env, deps)).status).toBe(401);
    const ran = await handle(new Request("https://relay.example/v1/testflight/sync?token=files-token", { method: "POST" }), env, deps);
    expect(await ran.json()).toEqual({ filed: ["LYRE-200", "LYRE-201"] });
  });
});
