// Lyre's problem-report relay (README.md): takes a report from the app, checks it,
// keeps its files, and files it in Jira, or, for a problem already filed, notes that it
// happened again. The Jira credentials live here, as Worker secrets, never in the app.
//
//   POST /v1/reports         a report (report.ts) → { issue, repeat }
//   GET  /v1/files/<key>     a report's file, with ?token=FILES_TOKEN

import {
  type Report, MAX_BODY_BYTES, validate, fingerprint, priority, labels, summary, description, repeatComment,
} from "./report";

export interface Env {
  JIRA_BASE_URL: string;
  JIRA_PROJECT: string;
  REPORTS_PER_HOUR: string;
  /** Secrets (wrangler secret put). */
  JIRA_EMAIL: string;
  JIRA_TOKEN: string;
  /** What the app sends in X-Lyre-Key: keeps out casual traffic (App Attest follows). */
  APP_KEY: string;
  /** For reading files back from GET /v1/files. */
  FILES_TOKEN: string;
  REPORTS: KVNamespace;
  FILES: R2Bucket;
}

/** The outside world, swapped for fakes in the tests. */
export interface Deps {
  fetch: typeof fetch;
  now: () => Date;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, { fetch: (input, init) => fetch(input, init), now: () => new Date() });
  },
};

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "POST" && url.pathname === "/v1/reports") return receive(request, env, deps);
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

  // A phone sending more than its share this hour is turned away.
  const hour = deps.now().toISOString().slice(0, 13);
  const rateKey = `rate:${report.installID}:${hour}`;
  const sent = Number((await env.REPORTS.get(rateKey)) ?? "0");
  if (sent >= Number(env.REPORTS_PER_HOUR)) return json({ error: "rate limited" }, 429);
  await env.REPORTS.put(rateKey, String(sent + 1), { expirationTtl: 7200 });

  const id = `${deps.now().toISOString().replace(/[:.]/g, "-")}-${crypto.randomUUID().slice(0, 8)}`;
  const fileKeys = await keepFiles(report, id, env);
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
    description: description(report, fileKeys, filesURL),
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
  return json({ issue, repeat: false }, 201);
}

/** The report's files, in R2 under the report's id; their keys, for the issue. */
async function keepFiles(report: Report, id: string, env: Env): Promise<string[]> {
  const keys: string[] = [];
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
  if (!env.FILES_TOKEN || url.searchParams.get("token") !== env.FILES_TOKEN) return json({ error: "unauthorised" }, 401);
  const key = decodeURIComponent(url.pathname.slice("/v1/files/".length));
  const object = await env.FILES.get(key);
  if (!object) return json({ error: "not found" }, 404);
  return new Response(object.body, {
    headers: { "Content-Type": object.httpMetadata?.contentType ?? "application/octet-stream" },
  });
}

function jira(env: Env, deps: Deps, path: string, body: unknown): Promise<Response> {
  return deps.fetch(`${env.JIRA_BASE_URL}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${env.JIRA_EMAIL}:${env.JIRA_TOKEN}`)}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(body),
  });
}

function url(request: Request): string {
  const u = new URL(request.url);
  return `${u.protocol}//${u.host}`;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
