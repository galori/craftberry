/**
 * App Attest verification for Cloudflare Workers.
 * Uses only Web Crypto (`crypto.subtle`), `TextDecoder` and `atob`. No nodejs_compat is needed.
 */
import { APPLE_ROOT_CA_G3_PEM } from './appleRootCAG3';
import { arrayOf, bytesOf, decodeComplete, decodeOne, type CBORValue, stringKeyedMap, textOf } from './cbor';
import { children, content, octets, readNode } from './der';
import { AppAttestError } from './errors';
import { verifyAttestationReceipt } from './receipt';
import { buf, bytesEqual, ecPoint, parseCert, pemToDer, verifyChain } from './x509';

export { AppAttestError, type AppAttestErrorCode } from './errors';

/** Add this token to `allowedBundleVersions` to accept attestations from OS releases without bundle-version data. */
export const LEGACY_BUNDLE_VERSION_TOKEN = 'legacy-no-bundle-version';

const NONCE_EXTENSION_OID = '1.2.840.113635.100.8.2';
const AAGUIDS = {
  development: ['appattestdevelop', 'appattestsandbox'],
  production: ['appattest\0\0\0\0\0\0\0'],
} as const;

export interface VerifyAttestationInput {
  keyId: string; // base64 (standard or URL-safe)
  attestationObject: Uint8Array;
  challenge: Uint8Array;
  appId: string; // TEAMID.bundleid
  environment: 'development' | 'production';
  allowedBundleVersions?: string[];
  appleRootCA: string; // PEM
  /** Optional extra. Root for the receipt signature; defaults to Apple Root CA - G3. */
  receiptRootCA?: string;
  /** Optional extra. Verification time for certificates and receipt age; defaults to now. */
  now?: Date;
}

export interface VerifiedAttestation {
  /** SubjectPublicKeyInfo DER of the attested P-256 key. */
  publicKeyDer: Uint8Array;
  receipt: Uint8Array;
  counter: number;
}

const sha256 = async (d: Uint8Array) => new Uint8Array(await crypto.subtle.digest('SHA-256', buf(d)));
const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
};
const u32 = (b: Uint8Array) => ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) >>> 0;
const ascii = (s: string) => Uint8Array.from(s, (c) => c.charCodeAt(0));

// P-256 SubjectPublicKeyInfo header; the 65-byte point follows.
const P256_SPKI_PREFIX = Uint8Array.from([
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
]);

function decodeKeyId(keyId: string): Uint8Array {
  const b64 = keyId.replace(/-/g, '+').replace(/_/g, '/');
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  let out: Uint8Array;
  try {
    out = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  } catch {
    throw new AppAttestError('invalid_key_identifier');
  }
  if (out.length !== 32) throw new AppAttestError('invalid_key_identifier');
  return out;
}

/** Validation category as an unsigned int, or a 4-byte value read big- or little-endian (first one under 7). */
function categoryValue(v: CBORValue | undefined): number | undefined {
  if (!v) return undefined;
  if (v.t === 'uint' && v.v <= 0xffffffffn) return Number(v.v);
  const b = bytesOf(v);
  if (!b || b.length !== 4) return undefined;
  const big = u32(b);
  const little = (b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)) >>> 0;
  return [big, little].find((x) => x < 7);
}
const categoryAllowed = (c: number, env: 'development' | 'production') => (env === 'development' ? c === 3 : [2, 4, 5].includes(c));

interface ParsedAuthData {
  rpIdHash: Uint8Array;
  counter: number;
  aaguid: Uint8Array;
  credentialId: Uint8Array;
  validationCategory?: number;
  bundleVersion?: string;
}

/** @internal exported for tests */
export function parseAttestationAuthData(data: Uint8Array): ParsedAuthData {
  const malformed = () => new AppAttestError('malformed_object');
  if (data.length < 55) throw malformed();
  const flags = data[32];
  if ((flags & 0x40) === 0) throw new AppAttestError('invalid_authenticator_flags');
  const credLen = (data[53] << 8) | data[54];
  const credEnd = 55 + credLen;
  if (credLen !== 32 || credEnd > data.length) throw malformed();
  const { value: cose, used } = decodeOne(data.subarray(credEnd));
  if (cose.t !== 'map') throw malformed();
  const ext = data.subarray(credEnd + used);
  const parsed: ParsedAuthData = {
    rpIdHash: data.slice(0, 32),
    counter: u32(data.subarray(33, 37)),
    aaguid: data.slice(37, 53),
    credentialId: data.slice(55, credEnd),
  };
  if (ext.length === 0) {
    if ((flags & 0x80) !== 0) throw new AppAttestError('invalid_extensions');
    return parsed;
  }
  // Apple's sample carries the extension map even with the ED flag clear. Accept one complete map, nothing else.
  let map: Map<string, CBORValue> | undefined;
  try {
    map = stringKeyedMap(decodeComplete(ext));
  } catch {
    throw new AppAttestError('invalid_extensions');
  }
  if (!map) throw new AppAttestError('invalid_extensions');
  if (map.has('apple_validation_category_01') || map.has('apple_bundle_version_01')) {
    const category = categoryValue(map.get('apple_validation_category_01'));
    const version = textOf(map.get('apple_bundle_version_01'));
    if (category === undefined || version === undefined) throw new AppAttestError('invalid_extensions');
    parsed.validationCategory = category;
    parsed.bundleVersion = version;
  }
  return parsed;
}

/** The App Attest nonce from a certificate, unwrapping both known encodings of the OCTET STRING. */
export function appAttestNonceExtension(certDer: Uint8Array): Uint8Array | undefined {
  const value = parseCert(certDer).extensions.get(NONCE_EXTENSION_OID);
  if (!value) return undefined;
  const seq = readNode(value, 0);
  if (seq.tag !== 0x30) return undefined;
  const fields = children(value, seq);
  if (fields.length !== 1) return undefined;
  if (fields[0].tag === 0x04) return octets(value, fields[0]);
  if (fields[0].tag !== 0xa1) return undefined;
  const inner = children(value, fields[0]);
  return inner.length === 1 && inner[0].tag === 0x04 ? octets(value, inner[0]) : undefined;
}

export async function verifyAttestation(input: VerifyAttestationInput): Promise<VerifiedAttestation> {
  const top = stringKeyedMap(decodeComplete(input.attestationObject));
  const stmt = stringKeyedMap(top?.get('attStmt'));
  const chainValues = arrayOf(stmt?.get('x5c'))?.map(bytesOf);
  const authData = bytesOf(top?.get('authData'));
  if (!top || textOf(top.get('fmt')) !== 'apple-appattest' || !stmt || !chainValues || chainValues.length < 2 || chainValues.some((c) => !c) || !authData) {
    throw new AppAttestError('malformed_object');
  }
  const receipt = bytesOf(stmt.get('receipt'));
  if (!receipt || receipt.length === 0) throw new AppAttestError('missing_receipt');

  const now = (input.now ?? new Date()).getTime();
  let chain: ReturnType<typeof parseCert>[];
  let anchor: ReturnType<typeof parseCert>;
  try {
    chain = (chainValues as Uint8Array[]).map((c) => parseCert(c));
    anchor = parseCert(pemToDer(input.appleRootCA));
  } catch {
    throw new AppAttestError('invalid_certificate_chain');
  }
  await verifyChain(chain, anchor, now, 'invalid_certificate_chain');
  const leaf = chain[0];
  const point = ecPoint(leaf);

  const keyBytes = decodeKeyId(input.keyId);
  if (!bytesEqual(await sha256(point), keyBytes)) throw new AppAttestError('invalid_key_identifier');

  const auth = parseAttestationAuthData(authData);
  if (!bytesEqual(auth.credentialId, keyBytes)) throw new AppAttestError('invalid_key_identifier');
  if (!bytesEqual(auth.rpIdHash, await sha256(new TextEncoder().encode(input.appId)))) throw new AppAttestError('invalid_app_identifier');
  if (auth.counter !== 0) throw new AppAttestError('invalid_counter');
  if (!AAGUIDS[input.environment].some((a) => bytesEqual(auth.aaguid, ascii(a)))) throw new AppAttestError('invalid_environment');

  const clientDataHash = await sha256(input.challenge);
  const nonce = await sha256(concat(authData, clientDataHash));
  const leafNonce = appAttestNonceExtension(leaf.der);
  if (!leafNonce || !bytesEqual(leafNonce, nonce)) throw new AppAttestError('invalid_challenge');

  const allowed = input.allowedBundleVersions;
  if (allowed) {
    const ok = auth.bundleVersion === undefined ? allowed.includes(LEGACY_BUNDLE_VERSION_TOKEN) : allowed.includes(auth.bundleVersion);
    if (!ok) throw new AppAttestError('invalid_extensions');
  }
  if (auth.validationCategory !== undefined && auth.bundleVersion !== undefined) {
    if (!categoryAllowed(auth.validationCategory, input.environment) || auth.bundleVersion === '') throw new AppAttestError('invalid_extensions');
  }

  await verifyAttestationReceipt({
    receipt,
    rootDer: pemToDer(input.receiptRootCA ?? APPLE_ROOT_CA_G3_PEM, 'invalid_receipt'),
    appId: input.appId,
    credentialCertificate: leaf.der,
    clientDataHash,
    now,
  });

  return { publicKeyDer: concat(P256_SPKI_PREFIX, point), receipt, counter: auth.counter };
}

export interface VerifyAssertionInput {
  assertion: Uint8Array;
  clientDataHash: Uint8Array;
  /** SPKI DER, or the raw 65-byte uncompressed point. */
  publicKeyDer: Uint8Array;
  appId: string;
  previousCounter: number;
}

export async function verifyAssertion(input: VerifyAssertionInput): Promise<{ counter: number }> {
  const values = stringKeyedMap(decodeComplete(input.assertion));
  const signature = bytesOf(values?.get('signature'));
  const authData = bytesOf(values?.get('authenticatorData'));
  if (!signature || !authData || authData.length < 37) throw new AppAttestError('malformed_object');

  if (!bytesEqual(authData.subarray(0, 32), await sha256(new TextEncoder().encode(input.appId)))) {
    throw new AppAttestError('invalid_assertion_app_identifier');
  }
  const flags = authData[32];
  if ((flags & 0x40) !== 0) throw new AppAttestError('invalid_authenticator_flags');
  const counter = u32(authData.subarray(33, 37));
  if (!(counter > input.previousCounter)) throw new AppAttestError('invalid_assertion_counter');

  // Real assertions are plain 37-byte authenticator data. If extension bytes are present, they must be one valid map.
  const ext = authData.subarray(37);
  if ((flags & 0x80) !== 0) {
    let map: Map<string, CBORValue> | undefined;
    try {
      map = stringKeyedMap(decodeComplete(ext));
    } catch {
      map = undefined;
    }
    if (!map) throw new AppAttestError('invalid_assertion_extensions');
    if (map.has('apple_validation_category_01') || map.has('apple_bundle_version_01')) {
      if (categoryValue(map.get('apple_validation_category_01')) === undefined || textOf(map.get('apple_bundle_version_01')) === undefined) {
        throw new AppAttestError('invalid_assertion_extensions');
      }
    }
  } else if (ext.length !== 0) {
    throw new AppAttestError('invalid_assertion_extensions');
  }

  const nonce = await sha256(concat(authData, input.clientDataHash));
  if (!(await verifyP256(input.publicKeyDer, signature, nonce))) throw new AppAttestError('invalid_assertion_signature');
  return { counter };
}

/** ECDSA P-256 over `message` (SHA-256 applied once by the verifier), DER-encoded signature. */
async function verifyP256(publicKey: Uint8Array, derSignature: Uint8Array, message: Uint8Array): Promise<boolean> {
  try {
    const spki = publicKey.length === 65 && publicKey[0] === 4 ? concat(P256_SPKI_PREFIX, publicKey) : publicKey;
    const key = await crypto.subtle.importKey('spki', buf(spki), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    const seq = readNode(derSignature, 0);
    const ints = children(derSignature, seq);
    if (seq.tag !== 0x30 || seq.end !== derSignature.length || ints.length !== 2 || ints.some((i) => i.tag !== 0x02)) return false;
    const rs = new Uint8Array(64);
    for (const [idx, n] of ints.entries()) {
      let v = content(derSignature, n);
      while (v.length > 32 && v[0] === 0) v = v.subarray(1);
      if (v.length === 0 || v.length > 32) return false;
      rs.set(v, idx * 32 + 32 - v.length);
    }
    return await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, buf(rs), buf(message));
  } catch {
    return false;
  }
}
