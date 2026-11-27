# Generation service

The `GenerationServer` Swift package executable serves the first-party versioned generation API. The service core, store protocol, and provider protocol are separated so a deployment can replace the HTTP, persistence, or provider adapters without changing request validation. The included executable is a small, single-process macOS host: the concrete App Attest verifier uses Apple Security, the listener uses POSIX sockets, and quota/session state uses SQLite.

## Routes

| Method and path | Purpose | Success |
|---|---|---|
| `POST /v1/session/challenge` | Create a one-time 32-byte App Attest challenge, valid for five minutes | `200` with `challengeID`, base64 `challenge`, and expiry |
| `POST /v1/session/enroll` | Validate an App Attest key attestation and consume its challenge atomically | `200` with an opaque session bearer token |
| `POST /v1/generate` | Generate a version 1 intent for the configured Bedrock profile | `200` with the fixture-compatible `ready` or `unsupported` intent document |

Generation requests use `intentVersion: 1`, `profileID: bedrock-stable-1.26.30`, and a non-empty prompt of at most 600 Swift characters. The service validates and assembles the model intent locally before returning it; the client independently performs the same local validation and assigns project IDs. Send an `Idempotency-Key` on generation requests. Each request also requires a fresh one-time challenge and App Attest assertion. The signed client data binds the challenge, request-body digest, route, and idempotency key. The server verifies the assertion signature against the already-computed SHA-256 nonce, App ID hash, bundle version, validation category, and monotonic counter, then consumes the challenge and advances the counter atomically in SQLite before reserving quota. Reuse of a challenge or counter is rejected with `401`. A retry keeps its idempotency key but must obtain a new challenge and assertion. Every provider attempt, including a retry after a provider failure or abandoned in-flight request, reserves one quota event; completed replays and requests rejected as already in progress do not. Thus the five-per-minute limit also bounds attempts made with a single idempotency key.

Errors use a JSON `error` code. Invalid or absent session tokens return `401 unauthorized`; quota limits return `429 quota_exceeded` with `Retry-After`; provider, database, and service failures return `503 service_unavailable`. Invalid input returns `400`, oversized bodies return `413`, and an in-flight duplicate or conflicting idempotency key returns `409`.

## Local launch

Build or run the executable from the repository root:

```sh
APP_ATTEST_APP_ID='<App ID prefix>.com.craftberry.app' \
APP_ATTEST_ENVIRONMENT='development' \
APP_ATTEST_ALLOWED_BUNDLE_VERSIONS='1' \
OPENAI_API_KEY='<server-only provider key>' \
GENERATION_DATABASE_PATH="$PWD/.scratch/generation-service.sqlite" \
swift run GenerationServer
```

`OPENAI_API_KEY` is read only by the server process and is never placed in the app bundle. Do not put real keys in shell history, tracked files, or this example. The listener defaults to `127.0.0.1:8787`; the database defaults to `craftberry-generation.sqlite` in the current directory. Keep the database on a durable local volume. SQLite WAL is intended for one host and must not be shared over NFS or used by multiple replicas.

`APP_ATTEST_ALLOWED_BUNDLE_VERSIONS` must list each accepted app build. App Attest data without bundle-version metadata is rejected when this list is configured unless it also includes the explicit `legacy-no-bundle-version` token. Add that token only when supporting OS releases that omit the metadata; it intentionally permits those clients without a verifiable build number.

## Staging and release setup still required

- Register the app's App ID in the Apple Developer account and enable App Attest. Set `APP_ATTEST_APP_ID` to the exact registered App ID (`prefix.bundle-id`); the prefix is not always the Team ID.
- Provision the iOS app with App Attest. Debug builds use the `development` entitlement; Release uses `production`. A real device, a valid signing profile, and Apple service access are needed to test enrollment end to end.
- Configure `CRAFTBERRY_BACKEND_BASE_URL` in the app's release build settings to the actual HTTPS service origin. No deployed URL is configured in this repository.
- Run the service on a managed macOS host with a persistent encrypted volume and backups for the SQLite file. Place it behind a trusted TLS reverse proxy, configure request-size and connection limits, and rate-limit unauthenticated challenge requests. Do not expose the listener's plain HTTP port directly to the Internet.
- The executable sets a restrictive process umask before creating the SQLite database. Keep its parent directory private as well, and include the WAL/SHM files in the same protected volume and backup policy.
- Supply the provider key through the host's secret manager as `OPENAI_API_KEY`, and set `APP_ATTEST_APP_ID`, `APP_ATTEST_ENVIRONMENT`, and the explicitly allowed `APP_ATTEST_ALLOWED_BUNDLE_VERSIONS` there. Use separate development and production databases and App Attest environments.
- Configure monitoring, secret rotation, database retention/backup, and a recovery process for session revocation. Session tokens are random 256-bit values; the database stores only their SHA-256 digests. This slice does not include a user account system, remote token revocation endpoint, or multi-host quota store.

The enrollment receipt is retained as opaque data alongside its App Attest key. The service does not yet independently validate the receipt's CMS signature and receipt fields, submit it to Apple's fraud-risk API, or consume the returned device risk metric. Before using a receipt for trust or risk decisions, add Apple's local receipt validation checks. Obtaining a fraud metric also requires an APNs-style JWT signing key with DeviceCheck enabled, plus separate development and production receipt handling; no account credentials are present here. Apple's server-validation guide describes the receipt checks and later assertions, while the fraud-risk guide documents the authenticated `attestationData` call. See [Apple's server validation guide](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server), [app integrity guide](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity), and [fraud-risk guide](https://developer.apple.com/documentation/devicecheck/assessing-fraud-risk).

The runnable host is intentionally macOS-only today. Certificate-chain trust uses Apple's `Security` framework; the request assertion uses CryptoKit. A Linux host adapter is feasible, but it needs a separately packaged service core and maintained portable cryptography: Swift Crypto provides a substantial CryptoKit-compatible API for Linux, and OpenSSL provides explicit X.509 chain-verification APIs. This is an implementation assessment, not a tested adapter; it would need valid and invalid chain fixtures, no-network trust evaluation against the pinned Apple root, and parity tests for assertion signatures before use. Do not replace the current validation with shelling out to a system `openssl` binary or with an unverified trust callback. See [Apple Swift Crypto](https://github.com/apple/swift-crypto) and [OpenSSL certificate verification](https://docs.openssl.org/3.5/man3/X509_verify_cert/).
