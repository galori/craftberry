import { readFileSync } from 'node:fs';
import { createHash, webcrypto } from 'node:crypto';
import { decodeComplete, stringKeyedMap, arrayOf, bytesOf } from '../../src/appattest/cbor';
import { verifyAttestationReceipt } from '../../src/appattest/receipt';
import {
  AppAttestError,
  appAttestNonceExtension,
  parseAttestationAuthData,
  verifyAssertion,
  verifyAttestation,
  type AppAttestErrorCode,
} from '../../src/appattest';

const dir = new URL('./fixtures/', import.meta.url);
const file = (n: string) => new Uint8Array(readFileSync(new URL(n, dir)));
const text = (n: string) => readFileSync(new URL(n, dir), 'utf8').trim();
const sha = (d: Uint8Array | string) => new Uint8Array(createHash('sha256').update(d).digest());
const pem = (der: Uint8Array) => `-----BEGIN CERTIFICATE-----\n${Buffer.from(der).toString('base64')}\n-----END CERTIFICATE-----`;

async function code(p: Promise<unknown>): Promise<AppAttestErrorCode | 'no error'> {
  try {
    await p;
    return 'no error';
  } catch (e) {
    if (e instanceof AppAttestError) return e.code;
    throw e;
  }
}

// ---- Attestation (synthetic fixture chain, as in the Swift tests) ----
const appId = text('app-id.txt');
const keyId = text('key-id.txt');
const challenge = file('challenge.bin');
const rootPem = pem(file('test-root.der'));
const receiptRootPem = pem(file('receipt-root.der'));
const receiptTime = new Date('2027-01-15T08:00:00Z');
const attestation = file('valid-attestation.cbor');
const base = {
  keyId,
  attestationObject: attestation,
  challenge,
  appId,
  environment: 'development' as const,
  allowedBundleVersions: ['1.0'],
  appleRootCA: rootPem,
  receiptRootCA: receiptRootPem,
  now: receiptTime,
};

describe('attestation', () => {
  it('accepts the valid fixture', async () => {
    const r = await verifyAttestation(base);
    expect(r.counter).toBe(0);
    expect(r.publicKeyDer.length).toBe(91);
    const x5c = arrayOf(stringKeyedMap(stringKeyedMap(decodeComplete(attestation))!.get('attStmt'))!.get('x5c'))!;
    expect(bytesOf(stringKeyedMap(stringKeyedMap(decodeComplete(attestation))!.get('attStmt'))!.get('receipt'))).toEqual(r.receipt);
    expect(x5c.length).toBeGreaterThanOrEqual(2);
    // The returned key is usable by verifyAssertion's key import.
    await webcrypto.subtle.importKey('spki', r.publicKeyDer, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
  });

  it('rejects a wrong challenge, app id, key id and environment', async () => {
    expect(await code(verifyAttestation({ ...base, challenge: new TextEncoder().encode('different-challenge') }))).toBe('invalid_challenge');
    expect(await code(verifyAttestation({ ...base, appId: 'OTHERTEAMID.com.craftberry.app' }))).toBe('invalid_app_identifier');
    expect(await code(verifyAttestation({ ...base, keyId: Buffer.alloc(32).toString('base64') }))).toBe('invalid_key_identifier');
    expect(await code(verifyAttestation({ ...base, keyId: 'not base64!' }))).toBe('invalid_key_identifier');
    expect(await code(verifyAttestation({ ...base, environment: 'production' }))).toBe('invalid_environment');
  });

  it('rejects an untrusted chain and a bundle version outside the allowlist', async () => {
    const apple = readFileSync(new URL('Apple_App_Attestation_Root_CA.pem', dir), 'utf8');
    expect(await code(verifyAttestation({ ...base, appleRootCA: apple }))).toBe('invalid_certificate_chain');
    expect(await code(verifyAttestation({ ...base, appleRootCA: 'garbage' }))).toBe('invalid_certificate_chain');
    expect(await code(verifyAttestation({ ...base, allowedBundleVersions: ['2.0'] }))).toBe('invalid_extensions');
  });

  it('rejects a chain checked outside its validity window', async () => {
    expect(await code(verifyAttestation({ ...base, now: new Date('2020-01-01T00:00:00Z') }))).toBe('invalid_certificate_chain');
  });

  it('accepts the extension map without the flag and rejects a wrong validation category', async () => {
    const open = { ...base, allowedBundleVersions: undefined };
    expect(await code(verifyAttestation({ ...open, attestationObject: file('wrong-validation-category-attestation.cbor') }))).toBe('invalid_extensions');
    const ok = await verifyAttestation({ ...open, attestationObject: file('missing-extension-flag-attestation.cbor') });
    expect(ok.counter).toBe(0);
  });

  it('rejects malformed objects and a missing receipt', async () => {
    expect(await code(verifyAttestation({ ...base, attestationObject: new Uint8Array([0xa0]) }))).toBe('malformed_object');
    expect(await code(verifyAttestation({ ...base, attestationObject: new Uint8Array([0x9f, 0xff]) }))).toBe('malformed_object');
  });

  it("unwraps Apple's published nonce extension without trust evaluation", () => {
    // Source sample: https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide
    const expected = Uint8Array.from([
      0x87, 0xb7, 0xd0, 0x6d, 0x93, 0xa4, 0x29, 0x4e, 0x46, 0xf0, 0x11, 0xe6, 0x6b, 0x6c, 0xc4, 0x00, 0xf0, 0xba, 0xb2, 0x07, 0x29, 0x97, 0x6c, 0x61, 0x95, 0x80, 0xb4,
      0x2a, 0xe6, 0x0b, 0xff, 0x6e,
    ]);
    expect(appAttestNonceExtension(file('apple-sample-leaf.der'))).toEqual(expected);
  });
});

describe('receipt', () => {
  const x5c = arrayOf(stringKeyedMap(stringKeyedMap(decodeComplete(attestation))!.get('attStmt'))!.get('x5c'))!;
  const leaf = bytesOf(x5c[0])!;
  const receipt = file('valid-receipt.cms');
  const input = {
    receipt,
    rootDer: file('receipt-root.der'),
    appId,
    credentialCertificate: leaf,
    clientDataHash: sha(challenge),
    now: receiptTime.getTime(),
  };

  it('checks CMS signature, trust and attestation bindings', async () => {
    expect(await code(verifyAttestationReceipt(input))).toBe('no error');
    const tampered = receipt.slice();
    tampered[tampered.length - 1] ^= 1;
    expect(await code(verifyAttestationReceipt({ ...input, receipt: tampered }))).toBe('invalid_receipt');
    expect(await code(verifyAttestationReceipt({ ...input, rootDer: new Uint8Array(input.rootDer.length) }))).toBe('invalid_receipt');
    expect(await code(verifyAttestationReceipt({ ...input, appId: 'OTHERTEAMID.com.craftberry.app' }))).toBe('invalid_receipt');
    expect(await code(verifyAttestationReceipt({ ...input, credentialCertificate: new TextEncoder().encode('another-key') }))).toBe('invalid_receipt');
    expect(await code(verifyAttestationReceipt({ ...input, clientDataHash: new Uint8Array(32) }))).toBe('invalid_receipt');
    expect(await code(verifyAttestationReceipt({ ...input, now: input.now + 301_000 }))).toBe('invalid_receipt');
  });
});

describe('authenticator data', () => {
  const cat = (n: number) => n; // keeps intent readable below
  const text8 = (s: string) => Uint8Array.from(cText(s));
  const cbor = (...parts: Uint8Array[]) => Uint8Array.from(parts.flatMap((p) => [...p]));
  const base55 = (flags: number) =>
    Uint8Array.from([...new Uint8Array(32).fill(0x11), flags, 0, 0, 0, 0, ...new Uint8Array(16).fill(0x22), 0, 32, ...new Uint8Array(32).fill(0x33), 0xa0]);

  it('keeps legacy data without the new extensions valid', () => {
    const plain = parseAttestationAuthData(base55(0x40));
    expect(plain.validationCategory).toBeUndefined();
    expect(plain.bundleVersion).toBeUndefined();

    const older = parseAttestationAuthData(cbor(base55(0xc0), Uint8Array.of(0xa1), text8('older_extension'), text8('legacy')));
    expect(older.bundleVersion).toBeUndefined();

    const trailing = parseAttestationAuthData(
      cbor(base55(0x40), Uint8Array.of(0xa2), text8('apple_validation_category_01'), Uint8Array.of(cat(3)), text8('apple_bundle_version_01'), text8('1.0')),
    );
    expect(trailing.validationCategory).toBe(3);
    expect(trailing.bundleVersion).toBe('1.0');
  });
});

describe('CBOR reader', () => {
  it('accepts a slice with a nonzero start index', () => {
    const encoded = Uint8Array.of(0xff, 0xa1, 0x61, 0x78, 0x01, 0xee);
    const v = stringKeyedMap(decodeComplete(encoded.subarray(1, 5)))!;
    expect(v.get('x')).toEqual({ t: 'uint', v: 1n });
  });
  it('rejects a length that would overflow offset math', () => {
    expect(() => decodeComplete(Uint8Array.of(0x5b, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff))).toThrow(AppAttestError);
  });
  it('rejects excessive nesting', () => {
    expect(() => decodeComplete(Uint8Array.from([...new Uint8Array(256).fill(0x81), 0]))).toThrow(AppAttestError);
  });
  it('rejects indefinite lengths and oversized collections', () => {
    expect(() => decodeComplete(Uint8Array.of(0x9f, 0x01, 0xff))).toThrow(AppAttestError);
    expect(() => decodeComplete(Uint8Array.of(0x5f, 0xff))).toThrow(AppAttestError);
    expect(() => decodeComplete(Uint8Array.of(0x99, 0x08, 0x01))).toThrow(AppAttestError); // array of 2049
  });
  it('rejects trailing bytes', () => {
    expect(() => decodeComplete(Uint8Array.of(0x01, 0x02))).toThrow(AppAttestError);
  });
});

// ---- Assertions (keys and signatures generated with Web Crypto) ----
const subtle = webcrypto.subtle;
const asnInt = (b: Uint8Array) => {
  let v = b;
  while (v.length > 1 && v[0] === 0) v = v.subarray(1);
  return v[0] & 0x80 ? Uint8Array.from([0, ...v]) : v;
};
const rawToDer = (sig: Uint8Array) => {
  const r = asnInt(sig.subarray(0, 32));
  const s = asnInt(sig.subarray(32));
  const body = [0x02, r.length, ...r, 0x02, s.length, ...s];
  return Uint8Array.from([0x30, body.length, ...body]);
};
const head = (major: number, n: number) => (n < 24 ? [(major << 5) | n] : n < 256 ? [(major << 5) | 24, n] : [(major << 5) | 25, n >> 8, n & 255]);
const cText = (s: string) => [...head(3, s.length), ...Buffer.from(s)];
const cBytes = (b: Uint8Array) => [...head(2, b.length), ...b];

async function makeKey() {
  const pair = (await subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'])) as webcrypto.CryptoKeyPair;
  return { priv: pair.privateKey, spki: new Uint8Array(await subtle.exportKey('spki', pair.publicKey)), raw: new Uint8Array(await subtle.exportKey('raw', pair.publicKey)) };
}

async function makeAssertion(
  priv: webcrypto.CryptoKey,
  clientData: string,
  o: { counter: number; app?: string; bundleVersion?: string; extensions?: 'apple' | 'legacy' | 'none'; signAsDigest?: boolean },
) {
  const ext = o.extensions ?? 'none';
  const extBytes =
    ext === 'apple'
      ? [0xa2, ...cText('apple_validation_category_01'), 3, ...cText('apple_bundle_version_01'), ...cText(o.bundleVersion ?? '1.0')]
      : ext === 'legacy'
        ? [0xa1, ...cText('older_extension'), ...cText('legacy')]
        : [];
  const c = o.counter;
  const authData = Uint8Array.from([...sha(o.app ?? appId), ext === 'none' ? 0 : 0x80, c >>> 24, (c >>> 16) & 255, (c >>> 8) & 255, c & 255, ...extBytes]);
  const clientDataHash = sha(clientData);
  const nonce = sha(Uint8Array.from([...authData, ...clientDataHash]));
  // Apple signs the nonce as a message, so ECDSA-SHA256 hashes it once more. signAsDigest builds the old, wrong form.
  const rawSig = new Uint8Array(await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, priv, o.signAsDigest ? sha(nonce) : nonce));
  void o.signAsDigest;
  const assertion = Uint8Array.from([0xa2, ...cText('signature'), ...cBytes(rawToDer(rawSig)), ...cText('authenticatorData'), ...cBytes(authData)]);
  return { assertion, clientDataHash };
}

describe('assertion', () => {
  it('binds client data and enforces counter, app id and extensions', async () => {
    const key = await makeKey();
    const common = { publicKeyDer: key.spki, appId, previousCounter: 0 };
    const good = await makeAssertion(key.priv, 'canonical signed client data', { counter: 1, extensions: 'apple' });
    expect((await verifyAssertion({ ...common, ...good })).counter).toBe(1);

    // The raw 65-byte point is accepted as the key too.
    expect((await verifyAssertion({ ...common, ...good, publicKeyDer: key.raw })).counter).toBe(1);

    // Plain 37-byte authenticator data, the shape real devices send.
    const plain = await makeAssertion(key.priv, 'plain assertion', { counter: 1 });
    expect(plain.assertion.length).toBeGreaterThan(0);
    expect((await verifyAssertion({ ...common, ...plain })).counter).toBe(1);

    // Older OS extension map without Apple keys.
    const legacy = await makeAssertion(key.priv, 'legacy', { counter: 1, extensions: 'legacy' });
    expect((await verifyAssertion({ ...common, ...legacy })).counter).toBe(1);

    expect(await code(verifyAssertion({ ...common, assertion: good.assertion, clientDataHash: sha('different client data') }))).toBe('invalid_assertion_signature');

    const other = await makeKey();
    const forged = await makeAssertion(other.priv, 'canonical signed client data', { counter: 2, extensions: 'apple' });
    expect(await code(verifyAssertion({ ...common, ...forged }))).toBe('invalid_assertion_signature');

    // Signature over SHA256(nonce) as a pre-hashed digest of the nonce is the wrong form and must fail.
    const wrong = await makeAssertion(key.priv, 'canonical signed client data', { counter: 2, signAsDigest: true });
    expect(await code(verifyAssertion({ ...common, ...wrong }))).toBe('invalid_assertion_signature');

    const replay = await makeAssertion(key.priv, 'x', { counter: 0 });
    expect(await code(verifyAssertion({ ...common, ...replay }))).toBe('invalid_assertion_counter');
    const same = await makeAssertion(key.priv, 'x', { counter: 5 });
    expect(await code(verifyAssertion({ ...common, ...same, previousCounter: 5 }))).toBe('invalid_assertion_counter');

    expect(await code(verifyAssertion({ ...common, ...good, appId: 'OTHERTEAMID.com.craftberry.app' }))).toBe('invalid_assertion_app_identifier');
    expect(await code(verifyAssertion({ ...common, assertion: new Uint8Array([0xa0]), clientDataHash: good.clientDataHash }))).toBe('malformed_object');
    expect(await code(verifyAssertion({ ...common, ...good, publicKeyDer: new Uint8Array(5) }))).toBe('invalid_assertion_signature');
  });

  it('rejects a malformed extension map in the authenticator data', async () => {
    const key = await makeKey();
    const a = await makeAssertion(key.priv, 'x', { counter: 1, extensions: 'apple' });
    // Flag says extensions follow, but break the map by truncating authenticatorData is signed over, so rebuild by hand.
    const authData = Uint8Array.from([...sha(appId), 0x80, 0, 0, 0, 1, 0xa1]);
    const nonce = sha(Uint8Array.from([...authData, ...a.clientDataHash]));
    const sig = new Uint8Array(await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key.priv, nonce));
    const assertion = Uint8Array.from([0xa2, ...cText('signature'), ...cBytes(rawToDer(sig)), ...cText('authenticatorData'), ...cBytes(authData)]);
    expect(await code(verifyAssertion({ assertion, clientDataHash: a.clientDataHash, publicKeyDer: key.spki, appId, previousCounter: 0 }))).toBe(
      'invalid_assertion_extensions',
    );
  });
});
