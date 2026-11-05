// App Attest (Apple's DeviceCheck): a report counts as from a genuine copy of Lyre on a
// real Apple device only if it's signed by a key Apple has vouched for.
//
//   once per install   Lyre makes a key and has Apple attest it, over a challenge from
//                      the relay; verifyAttestation checks Apple's certificate chain to
//                      the App Attestation root, that the key is Lyre's (app ID) and that
//                      it answers this challenge, and gives back the key to keep.
//   each report        Lyre signs the report's bytes with the key (an assertion);
//                      verifyAssertion checks the signature, that it's Lyre's, and that
//                      its counter has gone up (no replays).
//
// Following "Validating apps that connect to your server" (Apple's developer docs).

// @peculiar/x509 needs Reflect's metadata API first, for the injection it uses inside.
import "reflect-metadata";
import * as x509 from "@peculiar/x509";

x509.cryptoProvider.set(crypto);

/** Apple App Attestation Root CA (apple.com/certificateauthority), valid 2020–2045,
 *  SHA-256 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32. */
export const APPLE_APP_ATTESTATION_ROOT = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

/** The attestation's nonce, in the credential certificate. */
const NONCE_OID = "1.2.840.113635.100.8.2";
const AAGUID_PRODUCTION = new Uint8Array([...new TextEncoder().encode("appattest"), 0, 0, 0, 0, 0, 0, 0]);
const AAGUID_DEVELOPMENT = new TextEncoder().encode("appattestdevelop");

export interface AttestedKey {
  /** The key's public half, SubjectPublicKeyInfo, base64. */
  publicKey: string;
  counter: number;
  environment: "production" | "development";
}

// MARK: Attestation

export async function verifyAttestation(params: {
  attestation: string; // base64 CBOR
  keyID: string;       // base64: SHA-256 of the key's public point
  challenge: Uint8Array;
  appID: string;       // TEAMID.bundle.id
  roots?: string[];    // PEM; Apple's by default (tests give their own)
  now?: Date;
}): Promise<{ key: AttestedKey } | { error: string }> {
  let object: Record<string, unknown>;
  try {
    object = decodeCBOR(base64ToBytes(params.attestation)) as Record<string, unknown>;
  } catch {
    return { error: "attestation isn't CBOR" };
  }
  if (object.fmt !== "apple-appattest") return { error: "not an App Attest attestation" };
  const statement = object.attStmt as { x5c?: Uint8Array[] } | undefined;
  const authData = object.authData as Uint8Array | undefined;
  if (!statement?.x5c || statement.x5c.length < 2 || !(authData instanceof Uint8Array)) return { error: "attestation incomplete" };

  // 1. The chain: credential certificate ← intermediate ← Apple's root, all in date.
  const now = params.now ?? new Date();
  const credential = new x509.X509Certificate(statement.x5c[0]);
  const intermediate = new x509.X509Certificate(statement.x5c[1]);
  const roots = (params.roots ?? [APPLE_APP_ATTESTATION_ROOT]).map((pem) => new x509.X509Certificate(pem));
  if (!(await credential.verify({ publicKey: intermediate.publicKey, date: now }))) return { error: "credential certificate not signed by the intermediate" };
  let chained = false;
  for (const root of roots) {
    if (await intermediate.verify({ publicKey: root.publicKey, date: now })) chained = true;
  }
  if (!chained) return { error: "intermediate not signed by the App Attestation root" };

  // 2–4. The nonce: SHA-256 of authData and the challenge's hash, in the certificate.
  const clientDataHash = await sha256(params.challenge);
  const nonce = await sha256(concat(authData, clientDataHash));
  const extension = credential.getExtension(NONCE_OID);
  if (!extension) return { error: "no nonce in the credential certificate" };
  const value = new Uint8Array(extension.value);
  const certNonce = value.slice(-32);
  if (value[value.length - 34] !== 0x04 || value[value.length - 33] !== 0x20 || !equal(certNonce, nonce)) {
    return { error: "nonce doesn't match this challenge" };
  }

  // 5. The key: its public point hashes to the key ID.
  const spki = new Uint8Array(credential.publicKey.rawData);
  const point = spki.slice(-65);
  const keyID = base64ToBytes(params.keyID);
  if (!equal(await sha256(point), keyID)) return { error: "key ID doesn't match the certificate's key" };

  // 6–9. authData: Lyre's app ID, a fresh key (counter 0), App Attest's AAGUID, this key.
  const parsed = parseAuthData(authData);
  if (!parsed.credentialID) return { error: "authData has no credential" };
  if (!equal(parsed.rpIDHash, await sha256(new TextEncoder().encode(params.appID)))) return { error: "not Lyre's app ID" };
  if (parsed.counter !== 0) return { error: "counter isn't 0" };
  let environment: AttestedKey["environment"];
  if (equal(parsed.aaguid!, AAGUID_PRODUCTION)) environment = "production";
  else if (equal(parsed.aaguid!, AAGUID_DEVELOPMENT)) environment = "development";
  else return { error: "not App Attest's AAGUID" };
  if (!equal(parsed.credentialID, keyID)) return { error: "credential ID doesn't match the key ID" };

  return { key: { publicKey: bytesToBase64(spki), counter: 0, environment } };
}

// MARK: Assertion

export async function verifyAssertion(params: {
  assertion: string;      // base64 CBOR { signature, authenticatorData }
  clientData: Uint8Array; // the report's bytes, as sent
  key: AttestedKey;
  appID: string;
}): Promise<{ counter: number } | { error: string }> {
  let object: { signature?: Uint8Array; authenticatorData?: Uint8Array };
  try {
    object = decodeCBOR(base64ToBytes(params.assertion)) as typeof object;
  } catch {
    return { error: "assertion isn't CBOR" };
  }
  if (!(object.signature instanceof Uint8Array) || !(object.authenticatorData instanceof Uint8Array)) return { error: "assertion incomplete" };
  const nonce = await sha256(concat(object.authenticatorData, await sha256(params.clientData)));
  const publicKey = await crypto.subtle.importKey("spki", base64ToBytes(params.key.publicKey),
                                                  { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, derToRaw(object.signature), nonce);
  if (!valid) return { error: "signature doesn't verify" };
  const parsed = parseAuthData(object.authenticatorData);
  if (!equal(parsed.rpIDHash, await sha256(new TextEncoder().encode(params.appID)))) return { error: "not Lyre's app ID" };
  if (parsed.counter <= params.key.counter) return { error: "counter hasn't gone up" };
  return { counter: parsed.counter };
}

// MARK: Parts

export function parseAuthData(data: Uint8Array) {
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const rpIDHash = data.slice(0, 32);
  const flags = data[32];
  const counter = view.getUint32(33);
  if (!(flags & 0x40) || data.length < 55) return { rpIDHash, flags, counter };
  const aaguid = data.slice(37, 53);
  const length = view.getUint16(53);
  const credentialID = data.slice(55, 55 + length);
  return { rpIDHash, flags, counter, aaguid, credentialID };
}

/** An ECDSA signature from DER (Apple's) to the raw r‖s WebCrypto takes. */
export function derToRaw(der: Uint8Array): Uint8Array {
  let offset = 2;
  if (der[1] & 0x80) offset = 2 + (der[1] & 0x7f);
  const read = () => {
    const length = der[offset + 1];
    let value = der.slice(offset + 2, offset + 2 + length);
    offset += 2 + length;
    while (value.length > 32 && value[0] === 0) value = value.slice(1);
    const padded = new Uint8Array(32);
    padded.set(value, 32 - value.length);
    return padded;
  };
  return concat(read(), read());
}

/** Enough CBOR for App Attest: maps, arrays, byte and text strings, unsigned ints. */
export function decodeCBOR(bytes: Uint8Array): unknown {
  let offset = 0;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const length = (info: number): number => {
    if (info < 24) return info;
    if (info === 24) return bytes[offset++];
    if (info === 25) { const v = view.getUint16(offset); offset += 2; return v; }
    if (info === 26) { const v = view.getUint32(offset); offset += 4; return v; }
    if (info === 27) { const v = Number(view.getBigUint64(offset)); offset += 8; return v; }
    throw new Error("indefinite lengths aren't used");
  };
  const item = (): unknown => {
    const head = bytes[offset++];
    const major = head >> 5, info = head & 0x1f;
    switch (major) {
      case 0: return length(info);
      case 2: { const n = length(info); const v = bytes.slice(offset, offset + n); offset += n; return v; }
      case 3: { const n = length(info); const v = new TextDecoder().decode(bytes.slice(offset, offset + n)); offset += n; return v; }
      case 4: { const n = length(info); return Array.from({ length: n }, item); }
      case 5: {
        const n = length(info);
        const map: Record<string, unknown> = {};
        for (let i = 0; i < n; i++) { const key = item(); map[String(key)] = item(); }
        return map;
      }
      default: throw new Error(`CBOR major type ${major} isn't used`);
    }
  };
  return item();
}

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

export function equal(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export function base64ToBytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}

export function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}
