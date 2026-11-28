import { AppAttestError, type AppAttestErrorCode } from './errors';
import { children, content, type DerNode, oid, octets, raw, readNode } from './der';

const OID = {
  ecPublicKey: '1.2.840.10045.2.1',
  rsaEncryption: '1.2.840.113549.1.1.1',
  p256: '1.2.840.10045.3.1.7',
  p384: '1.3.132.0.34',
  basicConstraints: '2.5.29.19',
};
const SIG_ALGS: Record<string, { kind: 'ecdsa' | 'rsa'; hash: 'SHA-256' | 'SHA-384' | 'SHA-512' }> = {
  '1.2.840.10045.4.3.2': { kind: 'ecdsa', hash: 'SHA-256' },
  '1.2.840.10045.4.3.3': { kind: 'ecdsa', hash: 'SHA-384' },
  '1.2.840.10045.4.3.4': { kind: 'ecdsa', hash: 'SHA-512' },
  '1.2.840.113549.1.1.11': { kind: 'rsa', hash: 'SHA-256' },
  '1.2.840.113549.1.1.12': { kind: 'rsa', hash: 'SHA-384' },
  '1.2.840.113549.1.1.13': { kind: 'rsa', hash: 'SHA-512' },
};
const HASH_OIDS: Record<string, 'SHA-256' | 'SHA-384' | 'SHA-512'> = {
  '2.16.840.1.101.3.4.2.1': 'SHA-256',
  '2.16.840.1.101.3.4.2.2': 'SHA-384',
  '2.16.840.1.101.3.4.2.3': 'SHA-512',
};

export const buf = (u: Uint8Array) => u as unknown as BufferSource;

export interface Cert {
  der: Uint8Array;
  tbs: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  spki: Uint8Array;
  serial: Uint8Array;
  sigAlg: string;
  signature: Uint8Array;
  notBefore: number;
  notAfter: number;
  isCA: boolean;
  /** Extension values by OID (raw OCTET STRING content). */
  extensions: Map<string, Uint8Array>;
  /** The BIT STRING content of subjectPublicKeyInfo, without the unused-bits byte. */
  publicKeyBits: Uint8Array;
}

const equal = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((x, i) => x === b[i]);
export { equal as bytesEqual };

function parseTime(data: Uint8Array, n: DerNode, code: AppAttestErrorCode): number {
  const s = new TextDecoder().decode(content(data, n));
  const m = n.tag === 0x17 ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?Z$/.exec(s) : /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s);
  if (!m || (n.tag !== 0x17 && n.tag !== 0x18)) throw new AppAttestError(code);
  let year = Number(m[1]);
  if (n.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6] ?? 0));
}

export function parseCert(der: Uint8Array): Cert {
  const bad = () => new AppAttestError('malformed_object');
  const top = readNode(der, 0);
  if (top.tag !== 0x30 || top.end !== der.length) throw bad();
  const [tbsNode, algNode, sigNode] = children(der, top);
  if (!tbsNode || !algNode || !sigNode || tbsNode.tag !== 0x30 || sigNode.tag !== 0x03) throw bad();
  const f = children(der, tbsNode);
  const o = f[0]?.tag === 0xa0 ? 1 : 0;
  // serial, sigAlg, issuer, validity, subject, spki
  if (f.length < o + 6) throw bad();
  const validity = children(der, f[o + 3]);
  if (validity.length !== 2) throw bad();
  const spki = f[o + 5];
  const spkiFields = children(der, spki);
  if (spkiFields.length !== 2 || spkiFields[1].tag !== 0x03) throw bad();
  const bits = content(der, spkiFields[1]);
  if (bits.length < 1 || bits[0] !== 0) throw bad();
  const sigBits = content(der, sigNode);
  if (sigBits.length < 1 || sigBits[0] !== 0) throw bad();

  const extensions = new Map<string, Uint8Array>();
  let isCA = false;
  const extWrap = f.find((n) => n.tag === 0xa3);
  if (extWrap) {
    const seq = children(der, extWrap)[0];
    for (const item of seq ? children(der, seq) : []) {
      const parts = children(der, item);
      if (item.tag !== 0x30 || parts.length < 2) throw bad();
      const id = oid(der, parts[0]);
      const octet = parts.find((p) => p.tag === 0x04);
      if (!octet) continue;
      const value = octets(der, octet);
      extensions.set(id, value);
      if (id === OID.basicConstraints) {
        const bc = children(value, readNode(value, 0));
        isCA = bc[0]?.tag === 0x01 && content(value, bc[0])[0] !== 0;
      }
    }
  }
  return {
    der,
    tbs: raw(der, tbsNode),
    serial: content(der, f[o]),
    issuer: raw(der, f[o + 2]),
    subject: raw(der, f[o + 4]),
    spki: raw(der, spki),
    sigAlg: oid(der, children(der, algNode)[0]),
    signature: sigBits.subarray(1),
    notBefore: parseTime(der, validity[0], 'malformed_object'),
    notAfter: parseTime(der, validity[1], 'malformed_object'),
    isCA,
    extensions,
    publicKeyBits: bits.subarray(1),
  };
}

/** The 65-byte uncompressed point of an EC leaf key, as Apple's key identifier is derived from it. */
export function ecPoint(cert: Cert): Uint8Array {
  const p = cert.publicKeyBits;
  if (p.length !== 65 || p[0] !== 4) throw new AppAttestError('malformed_object');
  return p;
}

/** Converts a DER ECDSA signature (SEQUENCE of r, s) to the fixed-width r||s form Web Crypto expects. */
function derSignatureToRaw(sig: Uint8Array, size: number): Uint8Array | undefined {
  try {
    const seq = readNode(sig, 0);
    if (seq.tag !== 0x30 || seq.end !== sig.length) return undefined;
    const ints = children(sig, seq);
    if (ints.length !== 2 || ints.some((i) => i.tag !== 0x02)) return undefined;
    const out = new Uint8Array(size * 2);
    for (const [idx, n] of ints.entries()) {
      let v = content(sig, n);
      while (v.length > size && v[0] === 0) v = v.subarray(1);
      if (v.length === 0 || v.length > size) return undefined;
      out.set(v, idx * size + (size - v.length));
    }
    return out;
  } catch {
    return undefined;
  }
}

function spkiCurve(spki: Uint8Array): { kind: 'ec'; curve: 'P-256' | 'P-384'; size: number } | { kind: 'rsa' } | undefined {
  const fields = children(spki, readNode(spki, 0));
  const alg = children(spki, fields[0]);
  const id = oid(spki, alg[0]);
  if (id === OID.rsaEncryption) return { kind: 'rsa' };
  if (id !== OID.ecPublicKey || !alg[1]) return undefined;
  const curve = oid(spki, alg[1]);
  if (curve === OID.p256) return { kind: 'ec', curve: 'P-256', size: 32 };
  if (curve === OID.p384) return { kind: 'ec', curve: 'P-384', size: 48 };
  return undefined;
}

/** Verifies `signature` over `data` with the key in `spki`, using a certificate-style signature algorithm OID. */
export async function verifyWithSpki(spki: Uint8Array, sigAlgOid: string, data: Uint8Array, signature: Uint8Array): Promise<boolean> {
  try {
    const alg = SIG_ALGS[sigAlgOid];
    const key = spkiCurve(spki);
    if (!alg || !key) return false;
    if (key.kind === 'ec') {
      if (alg.kind !== 'ecdsa') return false;
      const rawSig = derSignatureToRaw(signature, key.size);
      if (!rawSig) return false;
      const k = await crypto.subtle.importKey('spki', buf(spki), { name: 'ECDSA', namedCurve: key.curve }, false, ['verify']);
      return await crypto.subtle.verify({ name: 'ECDSA', hash: alg.hash }, k, buf(rawSig), buf(data));
    }
    if (alg.kind !== 'rsa') return false;
    const k = await crypto.subtle.importKey('spki', buf(spki), { name: 'RSASSA-PKCS1-v1_5', hash: alg.hash }, false, ['verify']);
    return await crypto.subtle.verify('RSASSA-PKCS1-v1_5', k, buf(signature), buf(data));
  } catch {
    return false;
  }
}

/** Maps a CMS digest-algorithm OID to a Web Crypto hash name. */
export const hashFromOid = (id: string) => HASH_OIDS[id];

/** Maps a CMS signature-algorithm OID (plain or hash-specific) to a certificate-style OID for `verifyWithSpki`. */
export function cmsSigAlgOid(sigOid: string, hash: string): string {
  if (SIG_ALGS[sigOid]) return sigOid;
  if (sigOid === OID.rsaEncryption) return { 'SHA-256': '1.2.840.113549.1.1.11', 'SHA-384': '1.2.840.113549.1.1.12', 'SHA-512': '1.2.840.113549.1.1.13' }[hash] ?? '';
  return '';
}

/**
 * Verifies `chain` (leaf first, each signed by the next) up to `root`, which is the trust anchor.
 * Each certificate must be valid at `at`, and every issuer must be a CA.
 */
export async function verifyChain(chain: Cert[], root: Cert, at: number, code: AppAttestErrorCode): Promise<void> {
  const fail = () => new AppAttestError(code);
  if (chain.length === 0) throw fail();
  const all = [...chain, root];
  for (const c of all) if (at < c.notBefore || at > c.notAfter) throw fail();
  for (let i = 0; i < chain.length; i++) {
    const issuer = all[i + 1];
    if (!equal(chain[i].issuer, issuer.subject) || !issuer.isCA) throw fail();
    if (!(await verifyWithSpki(issuer.spki, chain[i].sigAlg, chain[i].tbs, chain[i].signature))) throw fail();
  }
}

export function pemToDer(pem: string, code: AppAttestErrorCode = 'invalid_certificate_chain'): Uint8Array {
  const body = pem.replace(/-----BEGIN CERTIFICATE-----/, '').replace(/-----END CERTIFICATE-----[\s\S]*$/, '').replace(/\s+/g, '');
  try {
    if (!body) throw new Error('empty');
    return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  } catch {
    throw new AppAttestError(code);
  }
}
