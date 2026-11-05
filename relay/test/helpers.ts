import type { Report } from "../src/report";

// Fakes for the Worker's world: KV and R2 in memory, and a Jira that records what it's
// asked and answers like Jira Cloud.

export class MemoryKV {
  data = new Map<string, string>();
  async get(key: string, type?: string) {
    const value = this.data.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) : value;
  }
  async put(key: string, value: string) { this.data.set(key, value); }
  async delete(key: string) { this.data.delete(key); }
}

export class MemoryR2 {
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

export function fakeJira(options: { rejectPriority?: boolean } = {}) {
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

export const installID = "8B0F3C2E-1D4A-4E6B-9C7D-2A5F8E1B3C4D";

export function report(overrides: Partial<Report> = {}): Report {
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

