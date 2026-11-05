// What a report from Lyre carries, how it's checked, how repeats are recognised, and
// what the Jira issue for it says. No I/O here: index.ts does the talking.

export type ReportKind = "user" | "metrickit" | "detector";

export interface Report {
  kind: ReportKind;
  /** A short name for what went wrong: "Crash", "Hang 2.4 s", "Library load failed". */
  title: string;
  /** What the listener wrote (a user report), if anything. */
  description?: string;
  /** For grouping repeats without a stack: the error's kind, the detector's name. */
  signature?: string;
  /** The call stack, as text, if there is one (MetricKit's, Lyre's frames first). */
  stack?: string;
  app: { version: string; build: string; binaryUUID?: string; player?: string };
  device: { model: string; os: string };
  /** A random id the app made for itself: rate limits, nothing more. */
  installID: string;
  /** The last lines of Lyre's diagnostics log. */
  logTail?: string;
  /** Larger things, kept in R2 and linked from the issue. */
  files?: { name: string; contentType: string; base64: string }[];
}

export const MAX_BODY_BYTES = 4_000_000;

/** Checks a report's shape; returns what's wrong, or the report. */
export function validate(body: unknown): { report: Report } | { error: string } {
  if (typeof body !== "object" || body === null) return { error: "not an object" };
  const r = body as Partial<Report>;
  if (!r.kind || !["user", "metrickit", "detector"].includes(r.kind)) return { error: "bad kind" };
  if (typeof r.title !== "string" || r.title.length === 0 || r.title.length > 200) return { error: "bad title" };
  if (r.description !== undefined && (typeof r.description !== "string" || r.description.length > 5000)) {
    return { error: "bad description" };
  }
  if (!r.app || typeof r.app.version !== "string" || typeof r.app.build !== "string") return { error: "bad app" };
  if (!r.device || typeof r.device.model !== "string" || typeof r.device.os !== "string") return { error: "bad device" };
  if (typeof r.installID !== "string" || !/^[0-9A-Fa-f-]{36}$/.test(r.installID)) return { error: "bad installID" };
  if (r.files && (!Array.isArray(r.files) || r.files.length > 5)) return { error: "bad files" };
  return { report: r as Report };
}

/**
 * What makes two reports the same problem: the kind, the version, and the signature
 * or the stack's top frames with their addresses taken out (they differ build to
 * build and launch to launch). A user report is never grouped: each is someone's own.
 */
export async function fingerprint(report: Report): Promise<string | null> {
  if (report.kind === "user") return null;
  const frames = (report.stack ?? "")
    .split("\n")
    .map((line) => line.replace(/0x[0-9a-f]+/gi, "").replace(/\+ ?\d+/g, "").replace(/\s+/g, " ").trim())
    .filter((line) => line.length > 0)
    .slice(0, 8)
    .join("|");
  const key = [report.kind, report.app.version, report.signature ?? report.title, frames].join("#");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  return [...new Uint8Array(digest)].slice(0, 12).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export type Priority = "Highest" | "High" | "Medium" | "Low";

/** A crash matters most; then hangs and failures; a listener's own report is Medium. */
export function priority(report: Report): Priority {
  const t = report.title.toLowerCase();
  if (report.kind === "metrickit" && t.includes("crash")) return "High";
  if (t.includes("hang") || t.includes("failed") || t.includes("cpu")) return "Medium";
  if (report.kind === "user") return "Medium";
  return "Low";
}

/** The issue's labels: never `claude`; Daniel adds that after reviewing it. */
export function labels(report: Report): string[] {
  return ["auto-report", "needs-triage", `report-${report.kind}`];
}

export function summary(report: Report): string {
  const prefix = report.kind === "user" ? "[Reported]" : "[Auto]";
  return `${prefix} ${report.title} (${report.app.version} build ${report.app.build})`.slice(0, 250);
}

// MARK: The issue's description, in Atlassian Document Format (Jira Cloud's v3 API).

type ADFNode = Record<string, unknown>;

const text = (value: string): ADFNode => ({ type: "text", text: value });
const paragraph = (value: string): ADFNode => ({ type: "paragraph", content: value ? [text(value)] : [] });
const heading = (value: string): ADFNode => ({ type: "heading", attrs: { level: 3 }, content: [text(value)] });
const code = (value: string): ADFNode => ({ type: "codeBlock", attrs: {}, content: [text(value)] });

/**
 * Everything needed to start on it, in the text itself (attachments can't be read by
 * the triage that follows): what happened, on what, the stack, the log's last lines,
 * and where the full files are.
 */
export function description(report: Report, fileLinks: string[], reportURL: string, attested = false): ADFNode {
  const content: ADFNode[] = [];
  if (report.description) {
    content.push(heading("What the listener said"), paragraph(report.description));
  }
  content.push(
    heading("Where"),
    paragraph(
      `Lyre ${report.app.version} (${report.app.build})` +
        (report.app.binaryUUID ? `, binary ${report.app.binaryUUID}` : "") +
        (report.app.player ? `, ${report.app.player} player` : "") +
        `; ${report.device.model}, ${report.device.os}`
    ),
    paragraph(`Report kind: ${report.kind}` + (report.signature ? `; signature: ${report.signature}` : "")),
    paragraph(attested ? "Sent by an attested copy of Lyre (App Attest)." : "Not attested (sent with the app's key alone).")
  );
  if (report.stack) content.push(heading("Stack"), code(report.stack.slice(0, 12_000)));
  if (report.logTail) content.push(heading("Diagnostics log (last lines)"), code(report.logTail.slice(-12_000)));
  if (fileLinks.length > 0) {
    content.push(heading("Full files"), paragraph(fileLinks.map((link) => `${reportURL}/${link}`).join("\n")));
  }
  content.push(
    paragraph("Filed by Lyre's problem-report relay. Add the claude label to have it picked up by /jira-triage.")
  );
  return { type: "doc", version: 1, content };
}

/** A repeat: a comment on the issue it first became. */
export function repeatComment(report: Report, occurrences: number): ADFNode {
  return {
    type: "doc",
    version: 1,
    content: [
      paragraph(
        `Happened again (${occurrences} times so far): Lyre ${report.app.version} (${report.app.build}), ` +
          `${report.device.model}, ${report.device.os}.`
      ),
      ...(report.logTail ? [code(report.logTail.slice(-4_000))] : []),
    ],
  };
}
