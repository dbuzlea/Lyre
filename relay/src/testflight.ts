// The TestFlight bridge: what Lyre's testers send through TestFlight (feedback with
// screenshots, and crashes with their logs) reaches Jira as reports do. Every half hour
// the relay reads App Store Connect's API with an API key (ASC_KEY_ID, ASC_ISSUER_ID,
// ASC_PRIVATE_KEY, ASC_APP_ID) and files each submission it hasn't filed yet, from
// TESTFLIGHT_SINCE on (so turning it on doesn't file all the old ones).
//
// App Store Connect API: GET /v1/apps/{id}/betaFeedbackScreenshotSubmissions and
// …/betaFeedbackCrashSubmissions; a crash's log at /v1/betaFeedbackCrashSubmissions/{id}/crashLog.

import { bytesToBase64, base64ToBytes } from "./attest";

const ASC = "https://api.appstoreconnect.apple.com";

export interface Submission {
  id: string;
  kind: "feedback" | "crash";
  comment?: string;
  email?: string;
  deviceModel?: string;
  osVersion?: string;
  createdDate: string;
  build?: string;
  screenshots: { url: string; width?: number; height?: number }[];
}

/** A JWT for App Store Connect, signed ES256 with the API key; good for 20 minutes. */
export async function ascToken(keyID: string, issuerID: string, privateKeyPEM: string, now: Date): Promise<string> {
  const der = base64ToBytes(privateKeyPEM.replace(/-----[^-]+-----/g, "").replace(/\s+/g, ""));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const seconds = Math.floor(now.getTime() / 1000);
  const part = (value: unknown) => base64URL(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${part({ alg: "ES256", kid: keyID, typ: "JWT" })}.${part({
    iss: issuerID, iat: seconds, exp: seconds + 1200, aud: "appstoreconnect-v1",
  })}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key,
                                                            new TextEncoder().encode(unsigned)));
  return `${unsigned}.${base64URL(signature)}`;
}

function base64URL(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The app's submissions of one kind, newest first, with each one's build number. */
export async function listSubmissions(kind: Submission["kind"], appID: string, token: string,
                                      fetcher: typeof fetch): Promise<Submission[]> {
  const resource = kind === "feedback" ? "betaFeedbackScreenshotSubmissions" : "betaFeedbackCrashSubmissions";
  const response = await fetcher(`${ASC}/v1/apps/${appID}/${resource}?sort=-createdDate&limit=50&include=build&fields[builds]=version`,
                                 { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`App Store Connect ${resource}: ${response.status}`);
  const body = await response.json() as {
    data: { id: string; attributes: Record<string, any>; relationships?: { build?: { data?: { id: string } } } }[];
    included?: { type: string; id: string; attributes?: { version?: string } }[];
  };
  const builds = new Map((body.included ?? []).filter((i) => i.type === "builds").map((i) => [i.id, i.attributes?.version]));
  return body.data.map((item) => ({
    id: item.id,
    kind,
    comment: item.attributes.comment ?? undefined,
    email: item.attributes.email ?? undefined,
    deviceModel: item.attributes.deviceModel ?? undefined,
    osVersion: item.attributes.osVersion ?? undefined,
    createdDate: item.attributes.createdDate,
    build: builds.get(item.relationships?.build?.data?.id ?? ""),
    screenshots: (item.attributes.screenshots ?? []).map((s: any) => ({ url: s.url, width: s.width, height: s.height })),
  }));
}

export async function crashLog(id: string, token: string, fetcher: typeof fetch): Promise<string | undefined> {
  const response = await fetcher(`${ASC}/v1/betaFeedbackCrashSubmissions/${id}/crashLog`,
                                 { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) return undefined;
  return ((await response.json()) as { data?: { attributes?: { logText?: string } } }).data?.attributes?.logText;
}

// MARK: The issue

type ADFNode = Record<string, unknown>;
const text = (value: string): ADFNode => ({ type: "text", text: value });
const paragraph = (value: string): ADFNode => ({ type: "paragraph", content: value ? [text(value)] : [] });
const heading = (value: string): ADFNode => ({ type: "heading", attrs: { level: 3 }, content: [text(value)] });
const code = (value: string): ADFNode => ({ type: "codeBlock", attrs: {}, content: [text(value)] });

export function testflightSummary(s: Submission): string {
  const words = (s.comment ?? "").split("\n")[0].trim();
  const what = s.kind === "crash" ? "Crash" : "Feedback";
  return `[TestFlight] ${what}${words ? `: ${words}` : ""}${s.build ? ` (build ${s.build})` : ""}`.slice(0, 250);
}

export function testflightDescription(s: Submission, log: string | undefined, fileLinks: string[], filesURL: string): ADFNode {
  const content: ADFNode[] = [];
  if (s.comment) content.push(heading("What the tester said"), paragraph(s.comment));
  content.push(
    heading("Where"),
    paragraph(`TestFlight ${s.kind}${s.build ? `, build ${s.build}` : ""}; ${s.deviceModel ?? "?"}, iOS ${s.osVersion ?? "?"}; ${s.createdDate}`),
    paragraph(`Tester: ${s.email ?? "anonymous"}. App Store Connect submission ${s.id}.`)
  );
  if (log) content.push(heading("Crash log"), code(log.slice(0, 12_000)));
  if (fileLinks.length > 0) content.push(heading("Files"), paragraph(fileLinks.map((l) => `${filesURL}/${l}`).join("\n")));
  content.push(paragraph("Filed by Lyre's relay from TestFlight. Add the claude label to have it picked up by /jira-triage."));
  return { type: "doc", version: 1, content };
}
