import { AppAttestError } from './errors';

export interface DerNode {
  tag: number;
  start: number;
  contentStart: number;
  contentEnd: number;
  end: number;
  indefinite: boolean;
}

const bad = (code: 'malformed_object' | 'invalid_receipt' = 'malformed_object') => new AppAttestError(code);

/** Reads one DER/BER element at `start`. Indefinite lengths (BER) are accepted only on constructed elements. */
export function readNode(data: Uint8Array, start: number): DerNode {
  if (start + 2 > data.length) throw bad();
  const tag = data[start];
  if ((tag & 0x1f) === 0x1f) throw bad(); // high tag numbers are not used
  let off = start + 1;
  const first = data[off++];
  if (first === 0x80) {
    if ((tag & 0x20) === 0) throw bad();
    let cursor = off;
    for (let guard = 0; ; guard++) {
      if (guard > 4096 || cursor + 2 > data.length) throw bad();
      if (data[cursor] === 0 && data[cursor + 1] === 0) break;
      cursor = readNode(data, cursor).end;
    }
    return { tag, start, contentStart: off, contentEnd: cursor, end: cursor + 2, indefinite: true };
  }
  let length: number;
  if ((first & 0x80) === 0) {
    length = first;
  } else {
    const n = first & 0x7f;
    if (n === 0 || n > 4 || off + n > data.length) throw bad();
    length = 0;
    for (let i = 0; i < n; i++) length = length * 256 + data[off + i];
    off += n;
  }
  if (off + length > data.length) throw bad();
  return { tag, start, contentStart: off, contentEnd: off + length, end: off + length, indefinite: false };
}

export function children(data: Uint8Array, parent: DerNode): DerNode[] {
  const out: DerNode[] = [];
  let off = parent.contentStart;
  while (off < parent.contentEnd) {
    const c = readNode(data, off);
    if (c.end > parent.contentEnd) throw bad();
    out.push(c);
    off = c.end;
  }
  return out;
}

export const content = (data: Uint8Array, n: DerNode) => data.subarray(n.contentStart, n.contentEnd);
export const raw = (data: Uint8Array, n: DerNode) => data.subarray(n.start, n.end);

/** Content of an OCTET STRING, joining the pieces of a constructed (BER) one. */
export function octets(data: Uint8Array, n: DerNode): Uint8Array {
  if ((n.tag & 0x20) === 0) return content(data, n);
  const parts = children(data, n).map((c) => octets(data, c));
  const out = new Uint8Array(parts.reduce((a, p) => a + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

export function oid(data: Uint8Array, n: DerNode): string {
  if (n.tag !== 0x06) throw bad();
  const b = content(data, n);
  if (b.length === 0) throw bad();
  const first = Math.min(Math.floor(b[0] / 40), 2);
  const parts = [first, b[0] - first * 40];
  let v = 0;
  for (let i = 1; i < b.length; i++) {
    v = v * 128 + (b[i] & 0x7f);
    if ((b[i] & 0x80) === 0) {
      parts.push(v);
      v = 0;
    }
  }
  return parts.join('.');
}

/** Non-negative INTEGER of at most 6 bytes (receipt attribute types). */
export function smallInteger(data: Uint8Array, n: DerNode): number {
  const b = content(data, n);
  if (n.tag !== 0x02 || b.length === 0 || b.length > 6 || (b[0] & 0x80) !== 0) throw bad('invalid_receipt');
  let v = 0;
  for (const x of b) v = v * 256 + x;
  return v;
}
