import { AppAttestError } from './errors';

export type CBORValue =
  | { t: 'uint'; v: bigint }
  | { t: 'nint'; v: bigint }
  | { t: 'bytes'; v: Uint8Array }
  | { t: 'text'; v: string }
  | { t: 'array'; v: CBORValue[] }
  | { t: 'map'; v: [CBORValue, CBORValue][] }
  | { t: 'other' };

const MAX_DEPTH = 32;
const MAX_ITEMS = 2048;

const bad = () => new AppAttestError('malformed_object');

/** Decodes one CBOR item. Returns the value and the number of bytes consumed. */
export function decodeOne(data: Uint8Array): { value: CBORValue; used: number } {
  const r = new Reader(data);
  const value = r.read(0);
  return { value, used: r.offset };
}

/** Decodes exactly one CBOR item and rejects trailing bytes. */
export function decodeComplete(data: Uint8Array): CBORValue {
  const { value, used } = decodeOne(data);
  if (used !== data.length) throw bad();
  return value;
}

export function stringKeyedMap(v: CBORValue | undefined): Map<string, CBORValue> | undefined {
  if (!v || v.t !== 'map') return undefined;
  const out = new Map<string, CBORValue>();
  for (const [k, val] of v.v) if (k.t === 'text') out.set(k.v, val);
  return out;
}
export const bytesOf = (v: CBORValue | undefined) => (v?.t === 'bytes' ? v.v : undefined);
export const textOf = (v: CBORValue | undefined) => (v?.t === 'text' ? v.v : undefined);
export const arrayOf = (v: CBORValue | undefined) => (v?.t === 'array' ? v.v : undefined);

class Reader {
  offset = 0;
  constructor(private readonly data: Uint8Array) {}

  read(depth: number): CBORValue {
    if (depth > MAX_DEPTH) throw bad();
    if (this.offset >= this.data.length) throw bad();
    const initial = this.data[this.offset++];
    const major = initial >> 5;
    const len = this.readLength(initial & 0x1f); // rejects indefinite lengths (additional 31)
    switch (major) {
      case 0:
        return { t: 'uint', v: len };
      case 1:
        return { t: 'nint', v: -1n - len };
      case 2:
        return { t: 'bytes', v: this.readBytes(len) };
      case 3:
        try {
          return { t: 'text', v: new TextDecoder('utf-8', { fatal: true }).decode(this.readBytes(len)) };
        } catch {
          throw bad();
        }
      case 4: {
        const n = this.count(len);
        const items: CBORValue[] = [];
        for (let i = 0; i < n; i++) items.push(this.read(depth + 1));
        return { t: 'array', v: items };
      }
      case 5: {
        const n = this.count(len);
        const items: [CBORValue, CBORValue][] = [];
        for (let i = 0; i < n; i++) {
          const k = this.read(depth + 1);
          items.push([k, this.read(depth + 1)]);
        }
        return { t: 'map', v: items };
      }
      case 6:
        return this.read(depth + 1);
      default:
        return { t: 'other' };
    }
  }

  private count(len: bigint): number {
    if (len > BigInt(MAX_ITEMS)) throw bad();
    return Number(len);
  }

  private readLength(additional: number): bigint {
    if (additional < 24) return BigInt(additional);
    const size = { 24: 1, 25: 2, 26: 4, 27: 8 }[additional];
    if (size === undefined) throw bad();
    if (size > this.data.length - this.offset) throw bad();
    let v = 0n;
    for (let i = 0; i < size; i++) v = (v << 8n) | BigInt(this.data[this.offset + i]);
    this.offset += size;
    return v;
  }

  private readBytes(len: bigint): Uint8Array {
    if (len > BigInt(this.data.length - this.offset)) throw bad();
    const n = Number(len);
    const out = this.data.slice(this.offset, this.offset + n);
    this.offset += n;
    return out;
  }
}
