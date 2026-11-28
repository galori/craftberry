import { AppAttestError } from './errors';
import { children, content, type DerNode, oid, octets, raw, readNode, smallInteger } from './der';
import { buf, bytesEqual, cmsSigAlgOid, hashFromOid, parseCert, verifyChain, verifyWithSpki, type Cert } from './x509';

const OID_SIGNED_DATA = '1.2.840.113549.1.7.2';
const OID_MESSAGE_DIGEST = '1.2.840.113549.1.9.4';
const OID_SKI = '2.5.29.14';
const MAX_RECEIPT_AGE_MS = 5 * 60 * 1000;

const bad = () => new AppAttestError('invalid_receipt');

export interface ReceiptInput {
  receipt: Uint8Array;
  rootDer: Uint8Array;
  appId: string;
  credentialCertificate: Uint8Array;
  clientDataHash: Uint8Array;
  now: number;
}

/**
 * Verifies the CMS-signed attestation receipt: signature, trust chain to `rootDer` (at the receipt creation time)
 * and the bindings to the app id, credential certificate and client data hash.
 */
export async function verifyAttestationReceipt(input: ReceiptInput): Promise<void> {
  try {
    await verify(input);
  } catch (e) {
    if (e instanceof AppAttestError && e.code === 'invalid_receipt') throw e;
    throw bad();
  }
}

async function verify(input: ReceiptInput): Promise<void> {
  const d = input.receipt;
  const top = readNode(d, 0);
  if (top.tag !== 0x30 || top.end !== d.length) throw bad();
  const [typeNode, wrap] = children(d, top);
  if (!typeNode || !wrap || oid(d, typeNode) !== OID_SIGNED_DATA || wrap.tag !== 0xa0) throw bad();
  const sd = children(d, children(d, wrap)[0]);
  // version, digestAlgorithms, encapContentInfo, [0] certificates, [1] crls, signerInfos
  const encap = sd[2];
  const certsNode = sd.find((n) => n.tag === 0xa0);
  const signerSet = sd[sd.length - 1];
  if (!encap || !certsNode || !signerSet || signerSet.tag !== 0x31) throw bad();
  const signers = children(d, signerSet);
  if (signers.length !== 1) throw bad();

  const payloadWrap = children(d, encap)[1];
  if (!payloadWrap || payloadWrap.tag !== 0xa0) throw bad();
  const payloadOctet = children(d, payloadWrap)[0];
  if (!payloadOctet || (payloadOctet.tag !== 0x04 && payloadOctet.tag !== 0x24)) throw bad();
  const payload = octets(d, payloadOctet);

  const fields = parsePayload(payload);
  const creation = parseDate(fields.get(12));
  const bound = fields.get(3);
  const clientHash = fields.get(4);
  if (
    decodeString(fields.get(2)) !== input.appId ||
    !bound || !bytesEqual(bound, input.credentialCertificate) ||
    !clientHash || !bytesEqual(clientHash, input.clientDataHash) ||
    decodeString(fields.get(6)) !== 'ATTEST' ||
    creation > input.now ||
    input.now - creation > MAX_RECEIPT_AGE_MS
  ) {
    throw bad();
  }

  const pool = children(d, certsNode).map((n) => parseCert(raw(d, n).slice()));
  const si = children(d, signers[0]);
  // version, sid, digestAlgorithm, [0] signedAttrs, signatureAlgorithm, signature
  const signer = findSigner(d, si[1], pool);
  const hashName = hashFromOid(oid(d, children(d, si[2])[0]));
  const attrs = si.find((n) => n.tag === 0xa0);
  const sigAlgNode = si[attrs ? 4 : 3];
  const sigNode = si[attrs ? 5 : 4];
  if (!signer || !hashName || !sigAlgNode || !sigNode || sigNode.tag !== 0x04) throw bad();

  let signed: Uint8Array;
  if (attrs) {
    const digestAttr = children(d, attrs)
      .map((a) => children(d, a))
      .find((p) => p.length === 2 && oid(d, p[0]) === OID_MESSAGE_DIGEST);
    const expected = digestAttr && octets(d, children(d, digestAttr[1])[0]);
    const actual = new Uint8Array(await crypto.subtle.digest(hashName, buf(payload)));
    if (!expected || !bytesEqual(expected, actual)) throw bad();
    signed = raw(d, attrs).slice();
    signed[0] = 0x31; // signed attributes are signed as a SET, not as the [0] they are stored in
  } else {
    signed = payload;
  }
  const algOid = cmsSigAlgOid(oid(d, children(d, sigAlgNode)[0]), hashName);
  if (!(await verifyWithSpki(signer.spki, algOid, signed, octets(d, sigNode)))) throw bad();

  // Build the path from the signer up to a certificate issued by the root, using certificates carried in the message.
  const root = parseCert(input.rootDer);
  const path: Cert[] = [signer];
  while (!bytesEqual(path[path.length - 1].issuer, root.subject)) {
    const last = path[path.length - 1];
    const next = pool.find((c) => !path.includes(c) && bytesEqual(c.subject, last.issuer));
    if (!next || path.length > 5) throw bad();
    path.push(next);
  }
  await verifyChain(path, root, creation, 'invalid_receipt');
}

function findSigner(d: Uint8Array, sid: DerNode, pool: Cert[]): Cert | undefined {
  if (sid.tag === 0x30) {
    const [issuer, serial] = children(d, sid);
    return pool.find((c) => bytesEqual(c.issuer, raw(d, issuer)) && bytesEqual(c.serial, content(d, serial)));
  }
  if (sid.tag === 0x80) {
    const ski = content(d, sid);
    return pool.find((c) => {
      const v = c.extensions.get(OID_SKI);
      return v !== undefined && bytesEqual(v.subarray(2), ski);
    });
  }
  return undefined;
}

function parsePayload(data: Uint8Array): Map<number, Uint8Array> {
  const set = readNode(data, 0);
  if (set.tag !== 0x31 || set.end !== data.length) throw bad();
  const out = new Map<number, Uint8Array>();
  for (const attr of children(data, set)) {
    const p = children(data, attr);
    if (attr.tag !== 0x30 || p.length !== 3 || p[0].tag !== 0x02 || p[1].tag !== 0x02 || p[2].tag !== 0x04) throw bad();
    const type = smallInteger(data, p[0]);
    smallInteger(data, p[1]);
    if (out.has(type)) throw bad();
    out.set(type, octets(data, p[2]));
  }
  return out;
}

function decodeString(value: Uint8Array | undefined): string {
  if (!value) throw bad();
  const n = readNode(value, 0);
  if (![0x0c, 0x13, 0x16].includes(n.tag) || n.end !== value.length) throw bad();
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(content(value, n));
  } catch {
    throw bad();
  }
}

function parseDate(value: Uint8Array | undefined): number {
  if (!value) throw bad();
  const n = readNode(value, 0);
  if (n.tag !== 0x18 || n.end !== value.length) throw bad();
  const s = new TextDecoder().decode(content(value, n));
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(s)) throw bad();
  const t = Date.parse(s);
  if (Number.isNaN(t)) throw bad();
  return t;
}
