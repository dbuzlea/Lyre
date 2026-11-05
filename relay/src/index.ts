// Lyre's problem-report relay (README.md): takes a report from the app, checks it,
// keeps its files, and files it in Jira, or, for a problem already filed, notes that it
// happened again. The Jira credentials live here, as Worker secrets, never in the app.
//
//   GET  /v1/attest/challenge          a one-time challenge for App Attest (5 minutes)
//   POST /v1/attest                    { keyID, attestation, challenge }: Apple's
//                                      attestation of the app's key, checked and kept
//   POST /v1/reports         a report (report.ts) → { issue, repeat }; signed with the
//                            attested key (X-Lyre-Key-ID, X-Lyre-Assertion), or, while
//                            REQUIRE_ATTEST is off, with the app's key alone
//   GET  /v1/files/<key>     a report's file, with ?sig=… (that file's own signature,
//                            as the issue links it) or ?token=FILES_TOKEN
//
// A new issue also gets the report's files as Jira attachments, so a screenshot shows in
// Jira itself.

import {
  type Report, MAX_BODY_BYTES, validate, fingerprint, priority, labels, summary, description, repeatComment,
} from "./report";
import { type AttestedKey, verifyAttestation, verifyAssertion, base64ToBytes, bytesToBase64 } from "./attest";
import { type Submission, ascToken, listSubmissions, crashLog, testflightSummary, testflightDescription } from "./testflight";

export interface Env {
  JIRA_BASE_URL: string;
  JIRA_PROJECT: string;
  REPORTS_PER_HOUR: string;
  /** Lyre's app ID for App Attest: TEAMID.bundle.id. */
  APP_ID: string;
  /** "true" once every Lyre in use attests: then a report without an assertion is turned away. */
  REQUIRE_ATTEST: string;
  /** Tests' own App Attestation roots, in place of Apple's. */
  ATTEST_ROOTS?: string[];
  /** The TestFlight bridge (testflight.ts): the App Store Connect API key, and Lyre's app. */
  ASC_KEY_ID?: string;
  ASC_ISSUER_ID?: string;
  ASC_PRIVATE_KEY?: string;
  ASC_APP_ID?: string;
  /** Submissions from this date on are filed (ISO 8601). */
  TESTFLIGHT_SINCE?: string;
  /** The public address the relay's files are served from (for the bridge's links). */
  RELAY_URL?: string;
  /** Secrets (wrangler secret put). */
  JIRA_EMAIL: string;
  JIRA_TOKEN: string;
  /** What the app sends in X-Lyre-Key: keeps out casual traffic (App Attest follows). */
  APP_KEY: string;
  /** For reading files back from GET /v1/files. */
  FILES_TOKEN: string;
  REPORTS: KVNamespace;
  /** Where reports' files are kept. Optional: without R2 turned on for the account,
   *  reports are still filed, with everything but their files. */
  FILES?: R2Bucket;
}

/** The outside world, swapped for fakes in the tests. */
export interface Deps {
  fetch: typeof fetch;
  now: () => Date;
}

const live: Deps = { fetch: (input, init) => fetch(input, init), now: () => new Date() };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, live);
  },
  /** Every half hour (wrangler.toml): TestFlight's new submissions into Jira. */
  async scheduled(_event: ScheduledController, env: Env, context: ExecutionContext): Promise<void> {
    context.waitUntil(syncTestFlight(env, live));
  },
};

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/v1/attest/challenge") return challenge(env);
  if (request.method === "POST" && url.pathname === "/v1/attest") return attest(request, env, deps);
  if (request.method === "POST" && url.pathname === "/v1/reports") return receive(request, env, deps);
  // The TestFlight bridge, run now rather than at the half hour (files token).
  if (request.method === "POST" && url.pathname === "/v1/testflight/sync") {
    if (!env.FILES_TOKEN || url.searchParams.get("token") !== env.FILES_TOKEN) return json({ error: "unauthorised" }, 401);
    return json(await syncTestFlight(env, deps));
  }
  if (request.method === "GET" && url.pathname.startsWith("/v1/files/")) return file(url, env);
  return json({ error: "not found" }, 404);
}

async function receive(request: Request, env: Env, deps: Deps): Promise<Response> {
  if (request.headers.get("X-Lyre-Key") !== env.APP_KEY) return json({ error: "unauthorised" }, 401);
  const length = Number(request.headers.get("Content-Length") ?? "0");
  if (length > MAX_BODY_BYTES) return json({ error: "too large" }, 413);
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return json({ error: "too large" }, 413);

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "not JSON" }, 400);
  }
  const checked = validate(body);
  if ("error" in checked) return json({ error: checked.error }, 400);
  const report = checked.report;

  // From a genuine Lyre? Its signature over these exact bytes, with a key Apple vouched for.
  const attested = await checkAssertion(request, raw, env);
  if (attested === "invalid") return json({ error: "assertion invalid" }, 401);
  if (attested === "absent" && env.REQUIRE_ATTEST === "true") return json({ error: "attestation required" }, 401);

  // A phone sending more than its share this hour is turned away.
  const hour = deps.now().toISOString().slice(0, 13);
  const rateKey = `rate:${report.installID}:${hour}`;
  const sent = Number((await env.REPORTS.get(rateKey)) ?? "0");
  if (sent >= Number(env.REPORTS_PER_HOUR)) return json({ error: "rate limited" }, 429);
  await env.REPORTS.put(rateKey, String(sent + 1), { expirationTtl: 7200 });

  const id = `${deps.now().toISOString().replace(/[:.]/g, "-")}-${crypto.randomUUID().slice(0, 8)}`;
  const fileKeys = await keepFiles(report, id, env);
  // Each file's link carries its own signature, so it opens from the issue in a browser
  // without giving away the token that would open every file.
  const fileLinks = await Promise.all(fileKeys.map(async (key) =>
    `${key}?sig=${await signature(key, env.FILES_TOKEN)}`));
  const filesURL = `${url(request)}/v1/files`;

  // Already filed: a comment, and the count goes up.
  const print = await fingerprint(report);
  if (print) {
    const known = await env.REPORTS.get(`fp:${print}`, "json") as { issue: string; count: number } | null;
    if (known) {
      const count = known.count + 1;
      await env.REPORTS.put(`fp:${print}`, JSON.stringify({ issue: known.issue, count }));
      const commented = await jira(env, deps, `/rest/api/3/issue/${known.issue}/comment`,
                                   { body: repeatComment(report, count) });
      if (!commented.ok) return json({ error: "jira comment failed", status: commented.status }, 502);
      return json({ issue: known.issue, repeat: true, count });
    }
  }

  const fields: Record<string, unknown> = {
    project: { key: env.JIRA_PROJECT },
    issuetype: { name: "Bug" },
    summary: summary(report),
    description: description(report, fileLinks, filesURL, attested === "valid"),
    labels: labels(report),
    priority: { name: priority(report) },
  };
  let created = await jira(env, deps, "/rest/api/3/issue", { fields });
  // A project whose screen has no priority field turns the whole issue down: try again
  // without it.
  if (created.status === 400) {
    delete fields.priority;
    created = await jira(env, deps, "/rest/api/3/issue", { fields });
  }
  if (!created.ok) return json({ error: "jira create failed", status: created.status }, 502);
  const issue = ((await created.json()) as { key: string }).key;
  if (print) await env.REPORTS.put(`fp:${print}`, JSON.stringify({ issue, count: 1 }));
  // The files on the issue too, to see in Jira. The issue stands if this doesn't work:
  // the links are in its text.
  await attach(issue, report, env, deps);
  return json({ issue, repeat: false }, 201);
}

// MARK: The TestFlight Bridge

/** Files each TestFlight submission not filed yet, from TESTFLIGHT_SINCE on, oldest first. */
export async function syncTestFlight(env: Env, deps: Deps): Promise<{ filed: string[]; skipped?: string; error?: string }> {
  if (!env.ASC_KEY_ID || !env.ASC_ISSUER_ID || !env.ASC_PRIVATE_KEY || !env.ASC_APP_ID) return { filed: [], skipped: "no App Store Connect key" };
  const filed: string[] = [];
  try {
    const token = await ascToken(env.ASC_KEY_ID, env.ASC_ISSUER_ID, env.ASC_PRIVATE_KEY, deps.now());
    const since = env.TESTFLIGHT_SINCE ? Date.parse(env.TESTFLIGHT_SINCE) : 0;
    const submissions = [
      ...(await listSubmissions("feedback", env.ASC_APP_ID, token, deps.fetch)),
      ...(await listSubmissions("crash", env.ASC_APP_ID, token, deps.fetch)),
    ].filter((s) => Date.parse(s.createdDate) >= since)
     .sort((a, b) => Date.parse(a.createdDate) - Date.parse(b.createdDate));
    for (const submission of submissions) {
      if (await env.REPORTS.get(`tf:${submission.id}`)) continue;
      const issue = await fileSubmission(submission, token, env, deps);
      if (!issue) break; // Jira out of reach: the rest next time
      await env.REPORTS.put(`tf:${submission.id}`, issue);
      filed.push(issue);
    }
    return { filed };
  } catch (error) {
    return { filed, error: String(error) };
  }
}

async function fileSubmission(s: Submission, token: string, env: Env, deps: Deps): Promise<string | null> {
  const log = s.kind === "crash" ? await crashLog(s.id, token, deps.fetch) : undefined;
  // The screenshots (their URLs expire) and the log, kept and attached as a report's are.
  const files: { name: string; contentType: string; base64: string }[] = [];
  for (const [index, shot] of s.screenshots.slice(0, 5).entries()) {
    const response = await deps.fetch(shot.url);
    if (!response.ok) continue;
    files.push({ name: `screenshot-${index + 1}.jpg`, contentType: response.headers.get("Content-Type") ?? "image/jpeg",
                 base64: bytesToBase64(new Uint8Array(await response.arrayBuffer())) });
  }
  if (log) files.push({ name: "crash.ips", contentType: "text/plain", base64: bytesToBase64(new TextEncoder().encode(log)) });
  const asReport = { files } as unknown as Report;
  const id = `testflight-${s.id}`;
  const keys = await keepFiles(asReport, id, env);
  const links = await Promise.all(keys.map(async (key) => `${key}?sig=${await signature(key, env.FILES_TOKEN)}`));
  const created = await jira(env, deps, "/rest/api/3/issue", { fields: {
    project: { key: env.JIRA_PROJECT },
    issuetype: { name: "Bug" },
    summary: testflightSummary(s),
    description: testflightDescription(s, log, links, `${env.RELAY_URL ?? ""}/v1/files`),
    labels: ["auto-report", "needs-triage", "report-testflight"],
  } });
  if (!created.ok) return null;
  const issue = ((await created.json()) as { key: string }).key;
  await attach(issue, asReport, env, deps);
  return issue;
}

// MARK: App Attest

async function challenge(env: Env): Promise<Response> {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const value = bytesToBase64(bytes);
  await env.REPORTS.put(`challenge:${value}`, "1", { expirationTtl: 300 });
  return json({ challenge: value });
}

async function attest(request: Request, env: Env, deps: Deps): Promise<Response> {
  if (request.headers.get("X-Lyre-Key") !== env.APP_KEY) return json({ error: "unauthorised" }, 401);
  let body: { keyID?: string; attestation?: string; challenge?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "not JSON" }, 400);
  }
  if (!body.keyID || !body.attestation || !body.challenge) return json({ error: "incomplete" }, 400);
  // Each challenge answers once.
  if (!(await env.REPORTS.get(`challenge:${body.challenge}`))) return json({ error: "unknown or used challenge" }, 400);
  await env.REPORTS.delete(`challenge:${body.challenge}`);
  const result = await verifyAttestation({
    attestation: body.attestation, keyID: body.keyID, challenge: base64ToBytes(body.challenge),
    appID: env.APP_ID, roots: env.ATTEST_ROOTS, now: deps.now(),
  });
  if ("error" in result) return json({ error: result.error }, 400);
  await env.REPORTS.put(`attest:${body.keyID}`, JSON.stringify(result.key));
  return json({ environment: result.key.environment }, 201);
}

/** "valid", "invalid", or "absent" (no assertion sent). */
async function checkAssertion(request: Request, raw: string, env: Env): Promise<"valid" | "invalid" | "absent"> {
  const keyID = request.headers.get("X-Lyre-Key-ID");
  const assertion = request.headers.get("X-Lyre-Assertion");
  if (!keyID || !assertion) return "absent";
  const key = await env.REPORTS.get(`attest:${keyID}`, "json") as AttestedKey | null;
  if (!key) return "invalid";
  const result = await verifyAssertion({ assertion, clientData: new TextEncoder().encode(raw), key, appID: env.APP_ID });
  if ("error" in result) return "invalid";
  await env.REPORTS.put(`attest:${keyID}`, JSON.stringify({ ...key, counter: result.counter }));
  return "valid";
}

/** Adds the report's files to the issue as attachments. */
async function attach(issue: string, report: Report, env: Env, deps: Deps): Promise<void> {
  if (!report.files?.length) return;
  const form = new FormData();
  for (const f of report.files) {
    const bytes = Uint8Array.from(atob(f.base64), (c) => c.charCodeAt(0));
    form.append("file", new Blob([bytes], { type: f.contentType }), f.name.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 80));
  }
  try {
    await deps.fetch(`${env.JIRA_BASE_URL}/rest/api/3/issue/${issue}/attachments`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${env.JIRA_EMAIL}:${env.JIRA_TOKEN}`)}`,
        "X-Atlassian-Token": "no-check",
        Accept: "application/json",
      },
      body: form,
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    // Jira out of reach for the attachment: the issue's links still lead to the files.
  }
}

/** A file's own signature: an HMAC of its key under FILES_TOKEN. Opens that file only. */
export async function signature(key: string, secret: string): Promise<string> {
  const hmacKey = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
                                                { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", hmacKey, new TextEncoder().encode(key));
  return [...new Uint8Array(mac)].slice(0, 16).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The report's files, in R2 under the report's id; their keys, for the issue. */
async function keepFiles(report: Report, id: string, env: Env): Promise<string[]> {
  const keys: string[] = [];
  if (!env.FILES) return keys;
  for (const f of report.files ?? []) {
    const name = f.name.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 80);
    const key = `${id}/${name}`;
    const bytes = Uint8Array.from(atob(f.base64), (c) => c.charCodeAt(0));
    await env.FILES.put(key, bytes, { httpMetadata: { contentType: f.contentType } });
    keys.push(key);
  }
  return keys;
}

async function file(url: URL, env: Env): Promise<Response> {
  const key = decodeURIComponent(url.pathname.slice("/v1/files/".length));
  const sig = url.searchParams.get("sig");
  const allowed = !!env.FILES_TOKEN && (url.searchParams.get("token") === env.FILES_TOKEN
    || (sig !== null && sig === await signature(key, env.FILES_TOKEN)));
  if (!allowed) return json({ error: "unauthorised" }, 401);
  const object = await env.FILES?.get(key);
  if (!object) return json({ error: "not found" }, 404);
  return new Response(object.body, {
    headers: { "Content-Type": object.httpMetadata?.contentType ?? "application/octet-stream" },
  });
}

/** A call to Jira. Jira out of reach comes back as a 503 rather than throwing, so the
 *  app is told to try later (and keeps the report) instead of getting a crash. */
async function jira(env: Env, deps: Deps, path: string, body: unknown): Promise<Response> {
  try {
    return await deps.fetch(`${env.JIRA_BASE_URL}${path}`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${env.JIRA_EMAIL}:${env.JIRA_TOKEN}`)}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    return new Response("{}", { status: 503 });
  }
}

function url(request: Request): string {
  const u = new URL(request.url);
  return `${u.protocol}//${u.host}`;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
