import "reflect-metadata";
import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import * as x509 from "@peculiar/x509";
import { handle, type Env, type Deps } from "../src/index";
import { verifyAttestation, verifyAssertion, sha256, concat, bytesToBase64, type AttestedKey } from "../src/attest";
import { MemoryKV, MemoryR2, fakeJira, report } from "./helpers";

// A stand-in for Apple: a root and an intermediate of our own, and credential
// certificates made as Apple makes them (the nonce in 1.2.840.113635.100.8.2), so the
// relay's checks run against attestations it should take, and ones it shouldn't.

x509.cryptoProvider.set(crypto);
const appID = "28FC3LTQ82.com.pinkhatcreations.lyreapp";
const ecdsa = { name: "ECDSA", namedCurve: "P-256" } as const;
const signing = { name: "ECDSA", hash: "SHA-256" } as const;

let rootPEM: string;
let intermediateKeys: CryptoKeyPair;
let intermediate: x509.X509Certificate;

beforeAll(async () => {
  const rootKeys = await crypto.subtle.generateKey(ecdsa, true, ["sign", "verify"]) as CryptoKeyPair;
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    name: "CN=Test App Attestation Root CA", keys: rootKeys, signingAlgorithm: signing,
    notBefore: new Date("2020-01-01"), notAfter: new Date("2045-01-01"),
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  });
  rootPEM = root.toString("pem");
  intermediateKeys = await crypto.subtle.generateKey(ecdsa, true, ["sign", "verify"]) as CryptoKeyPair;
  intermediate = await x509.X509CertificateGenerator.create({
    subject: "CN=Test App Attestation CA 1", issuer: root.subject, publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey, signingAlgorithm: signing,
    notBefore: new Date("2020-01-01"), notAfter: new Date("2040-01-01"),
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  });
});

// MARK: A little CBOR, to write what Apple writes.

function cbor(value: unknown): Uint8Array {
  const head = (major: number, n: number) => n < 24 ? [major << 5 | n]
    : n < 256 ? [major << 5 | 24, n] : [major << 5 | 25, n >> 8, n & 0xff];
  if (value instanceof Uint8Array) return new Uint8Array([...head(2, value.length), ...value]);
  if (typeof value === "string") { const b = new TextEncoder().encode(value); return new Uint8Array([...head(3, b.length), ...b]); }
  if (typeof value === "number") return new Uint8Array(head(0, value));
  if (Array.isArray(value)) return concat(new Uint8Array(head(4, value.length)), ...value.map(cbor));
  const entries = Object.entries(value as Record<string, unknown>);
  return concat(new Uint8Array(head(5, entries.length)), ...entries.flatMap(([k, v]) => [cbor(k), cbor(v)]));
}

function rawToDER(raw: Uint8Array): Uint8Array {
  const integer = (bytes: Uint8Array) => {
    let b = bytes;
    while (b.length > 1 && b[0] === 0 && !(b[1] & 0x80)) b = b.slice(1);
    if (b[0] & 0x80) b = concat(new Uint8Array([0]), b);
    return concat(new Uint8Array([0x02, b.length]), b);
  };
  const body = concat(integer(raw.slice(0, 32)), integer(raw.slice(32)));
  return concat(new Uint8Array([0x30, body.length]), body);
}

const AAGUID_DEV = new TextEncoder().encode("appattestdevelop");

interface Device { keys: CryptoKeyPair; keyID: Uint8Array }

async function device(): Promise<Device> {
  const keys = await crypto.subtle.generateKey(ecdsa, true, ["sign", "verify"]) as CryptoKeyPair;
  const point = new Uint8Array(await crypto.subtle.exportKey("raw", keys.publicKey) as ArrayBuffer);
  return { keys, keyID: await sha256(point) };
}

/** What DCAppAttestService.attestKey hands back, as Apple would make it. */
async function attestation(d: Device, challenge: Uint8Array, options: { appID?: string; counter?: number } = {}) {
  const counter = new Uint8Array(4); new DataView(counter.buffer).setUint32(0, options.counter ?? 0);
  const length = new Uint8Array([0, d.keyID.length]);
  const authData = concat(await sha256(new TextEncoder().encode(options.appID ?? appID)), new Uint8Array([0x40]),
                          counter, AAGUID_DEV, length, d.keyID);
  const nonce = await sha256(concat(authData, await sha256(challenge)));
  // SEQUENCE { [1] { OCTET STRING nonce } }, as Apple encodes it.
  const extnValue = concat(new Uint8Array([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]), nonce);
  const credential = await x509.X509CertificateGenerator.create({
    subject: "CN=credential", issuer: intermediate.subject, publicKey: d.keys.publicKey,
    signingKey: intermediateKeys.privateKey, signingAlgorithm: signing,
    notBefore: new Date("2026-01-01"), notAfter: new Date("2027-01-01"),
    extensions: [new x509.Extension("1.2.840.113635.100.8.2", false, extnValue)],
  });
  return bytesToBase64(cbor({
    fmt: "apple-appattest",
    attStmt: { x5c: [new Uint8Array(credential.rawData), new Uint8Array(intermediate.rawData)], receipt: new Uint8Array([1]) },
    authData,
  }));
}

/** What DCAppAttestService.generateAssertion hands back for `clientData`. */
async function assertion(d: Device, clientData: Uint8Array, counter: number, options: { appID?: string } = {}) {
  const count = new Uint8Array(4); new DataView(count.buffer).setUint32(0, counter);
  const authenticatorData = concat(await sha256(new TextEncoder().encode(options.appID ?? appID)), new Uint8Array([0x00]), count);
  const nonce = await sha256(concat(authenticatorData, await sha256(clientData)));
  const raw = new Uint8Array(await crypto.subtle.sign(signing, d.keys.privateKey, nonce));
  return bytesToBase64(cbor({ signature: rawToDER(raw), authenticatorData }));
}

const now = new Date("2026-11-05T12:00:00Z");

describe("an attestation", () => {
  it("is taken from a genuine Lyre: Apple's chain, Lyre's app ID, this challenge, this key", async () => {
    const d = await device();
    const challenge = crypto.getRandomValues(new Uint8Array(32));
    const result = await verifyAttestation({ attestation: await attestation(d, challenge), keyID: bytesToBase64(d.keyID),
                                             challenge, appID, roots: [rootPEM], now });
    expect(result).toMatchObject({ key: { counter: 0, environment: "development" } });
  });

  it("isn't taken for another challenge (a replayed attestation)", async () => {
    const d = await device();
    const att = await attestation(d, new Uint8Array(32).fill(1));
    const result = await verifyAttestation({ attestation: att, keyID: bytesToBase64(d.keyID),
                                             challenge: new Uint8Array(32).fill(2), appID, roots: [rootPEM], now });
    expect(result).toEqual({ error: "nonce doesn't match this challenge" });
  });

  it("isn't taken for another app", async () => {
    const d = await device();
    const challenge = new Uint8Array(32).fill(3);
    const result = await verifyAttestation({ attestation: await attestation(d, challenge, { appID: "OTHER.app" }),
                                             keyID: bytesToBase64(d.keyID), challenge, appID, roots: [rootPEM], now });
    expect(result).toEqual({ error: "not Lyre's app ID" });
  });

  it("isn't taken without Apple's chain (someone's own CA)", async () => {
    const d = await device();
    const challenge = new Uint8Array(32).fill(4);
    const result = await verifyAttestation({ attestation: await attestation(d, challenge), keyID: bytesToBase64(d.keyID),
                                             challenge, appID, now }); // Apple's real root: our test chain isn't it
    expect(result).toEqual({ error: "intermediate not signed by the App Attestation root" });
  });

  it("isn't taken for a key it doesn't certify", async () => {
    const d = await device(), other = await device();
    const challenge = new Uint8Array(32).fill(5);
    const result = await verifyAttestation({ attestation: await attestation(d, challenge), keyID: bytesToBase64(other.keyID),
                                             challenge, appID, roots: [rootPEM], now });
    expect(result).toEqual({ error: "key ID doesn't match the certificate's key" });
  });
});

describe("an assertion", () => {
  async function attested(): Promise<{ d: Device; key: AttestedKey }> {
    const d = await device();
    const challenge = new Uint8Array(32).fill(6);
    const result = await verifyAttestation({ attestation: await attestation(d, challenge), keyID: bytesToBase64(d.keyID),
                                             challenge, appID, roots: [rootPEM], now });
    return { d, key: (result as { key: AttestedKey }).key };
  }

  it("is taken over the report's own bytes, its counter up", async () => {
    const { d, key } = await attested();
    const body = new TextEncoder().encode('{"kind":"user"}');
    expect(await verifyAssertion({ assertion: await assertion(d, body, 1), clientData: body, key, appID })).toEqual({ counter: 1 });
  });

  it("isn't taken for other bytes (a changed report)", async () => {
    const { d, key } = await attested();
    const signed = await assertion(d, new TextEncoder().encode("original"), 1);
    expect(await verifyAssertion({ assertion: signed, clientData: new TextEncoder().encode("changed"), key, appID }))
      .toEqual({ error: "signature doesn't verify" });
  });

  it("isn't taken again (a replay: the counter hasn't gone up)", async () => {
    const { d, key } = await attested();
    const body = new TextEncoder().encode("report");
    const signed = await assertion(d, body, 1);
    expect(await verifyAssertion({ assertion: signed, clientData: body, key: { ...key, counter: 1 }, appID }))
      .toEqual({ error: "counter hasn't gone up" });
  });
});

describe("the relay with App Attest", () => {
  let env: Env;
  let kv: MemoryKV;
  const deps = (jira: ReturnType<typeof fakeJira>): Deps => ({ fetch: jira.fetch, now: () => now });

  beforeEach(() => {
    kv = new MemoryKV();
    env = {
      JIRA_BASE_URL: "https://lyre-app.atlassian.net", JIRA_PROJECT: "LYRE", REPORTS_PER_HOUR: "10",
      APP_ID: appID, REQUIRE_ATTEST: "true", ATTEST_ROOTS: [rootPEM],
      JIRA_EMAIL: "someone@example.com", JIRA_TOKEN: "secret", APP_KEY: "app-key", FILES_TOKEN: "files-token",
      REPORTS: kv as unknown as KVNamespace, FILES: new MemoryR2() as unknown as R2Bucket,
    };
  });

  async function enrol(d: Device, jira: ReturnType<typeof fakeJira>) {
    const issued = await (await handle(new Request("https://relay.example/v1/attest/challenge"), env, deps(jira))).json() as { challenge: string };
    const challenge = Uint8Array.from(atob(issued.challenge), (c) => c.charCodeAt(0));
    return handle(new Request("https://relay.example/v1/attest", {
      method: "POST", headers: { "X-Lyre-Key": "app-key" },
      body: JSON.stringify({ keyID: bytesToBase64(d.keyID), attestation: await attestation(d, challenge), challenge: issued.challenge }),
    }), env, deps(jira));
  }

  function send(body: string, headers: Record<string, string>) {
    return new Request("https://relay.example/v1/reports", { method: "POST", headers: { "X-Lyre-Key": "app-key", ...headers }, body });
  }

  it("enrols a key once per challenge, then files its signed reports, marked attested", async () => {
    const jira = fakeJira();
    const d = await device();
    expect((await enrol(d, jira)).status).toBe(201);
    const body = JSON.stringify(report({ kind: "user", title: "Signed", stack: undefined }));
    const response = await handle(send(body, { "X-Lyre-Key-ID": bytesToBase64(d.keyID),
                                               "X-Lyre-Assertion": await assertion(d, new TextEncoder().encode(body), 1) }), env, deps(jira));
    expect(response.status).toBe(201);
    expect(JSON.stringify(jira.calls[0].body.fields.description)).toContain("Sent by an attested copy of Lyre");
  });

  it("turns away an unsigned report once attestation is required", async () => {
    const jira = fakeJira();
    const response = await handle(send(JSON.stringify(report()), {}), env, deps(jira));
    expect(response.status).toBe(401);
    expect(jira.calls).toHaveLength(0);
  });

  it("files an unsigned report while it isn't required yet, marked not attested", async () => {
    const jira = fakeJira();
    env.REQUIRE_ATTEST = "false";
    expect((await handle(send(JSON.stringify(report()), {}), env, deps(jira))).status).toBe(201);
    expect(JSON.stringify(jira.calls[0].body.fields.description)).toContain("Not attested");
  });

  it("turns away a forged signature, even while unsigned reports are allowed", async () => {
    const jira = fakeJira();
    env.REQUIRE_ATTEST = "false";
    const d = await device(), forger = await device();
    await enrol(d, jira);
    const body = JSON.stringify(report());
    const response = await handle(send(body, { "X-Lyre-Key-ID": bytesToBase64(d.keyID),
                                               "X-Lyre-Assertion": await assertion(forger, new TextEncoder().encode(body), 1) }), env, deps(jira));
    expect(response.status).toBe(401);
  });

  it("won't take a challenge twice", async () => {
    const jira = fakeJira();
    const d = await device();
    const issued = await (await handle(new Request("https://relay.example/v1/attest/challenge"), env, deps(jira))).json() as { challenge: string };
    const challenge = Uint8Array.from(atob(issued.challenge), (c) => c.charCodeAt(0));
    const att = await attestation(d, challenge);
    const post = () => handle(new Request("https://relay.example/v1/attest", { method: "POST", headers: { "X-Lyre-Key": "app-key" },
      body: JSON.stringify({ keyID: bytesToBase64(d.keyID), attestation: att, challenge: issued.challenge }) }), env, deps(jira));
    expect((await post()).status).toBe(201);
    expect((await post()).status).toBe(400);
  });
});
