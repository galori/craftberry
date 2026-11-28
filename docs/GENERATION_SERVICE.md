# Generation service

The `GenerationServer` Swift package executable serves the first-party versioned generation API. The service core, store protocol, and provider protocol are separated so a deployment can replace the HTTP, persistence, or provider adapters without changing request validation. The included executable is a small, single-process macOS host: the concrete App Attest verifier uses Apple Security, the listener uses POSIX sockets, and quota/session state uses SQLite.

## Routes

| Method and path | Purpose | Success |
|---|---|---|
| `POST /v1/session/challenge` | Create a one-time 32-byte App Attest challenge, valid for five minutes | `200` with `challengeID`, base64 `challenge`, and expiry |
| `POST /v1/session/enroll` | Validate an App Attest key attestation and consume its challenge atomically | `200` with an opaque session bearer token |
| `POST /v1/generate` | Generate a version 1 intent for the configured Bedrock profile | `200` with the fixture-compatible `ready` or `unsupported` intent document |

Generation requests use `intentVersion: 1`, `profileID: bedrock-stable-1.26.30`, and a non-empty prompt of at most 600 Swift characters. The service validates and assembles the model intent locally before returning it; the client independently performs the same local validation and assigns project IDs. Send an `Idempotency-Key` on generation requests. Each request also requires a fresh one-time challenge and App Attest assertion. The signed client data binds the challenge, request-body digest, route, and idempotency key. The server verifies the assertion signature (ECDSA-SHA256 over the nonce `SHA256(authenticatorData || SHA256(clientData))`, so the nonce is hashed once more by the signature), App ID hash, bundle version when present, validation category, and monotonic counter, then consumes the challenge and advances the counter atomically in SQLite before reserving quota. An out-of-order counter returns `409 assertion_counter_out_of_order`; the client retries with a fresh assertion and the same operation key. An unknown stored session returns `401 unknown_session`; the client re-enrolls only if that exact bearer is still the locally stored session. Other invalid assertions remain `401 unauthorized`. A retry keeps its idempotency key but must obtain a new challenge and assertion. The client keeps a pending key and canonical request body in memory until it gets a terminal result, so retrying the same prompt on the same client can resume after bounded polling times out. `generation_in_progress` remains resumable, and `idempotency_conflict` is terminal. Every provider attempt, including a retry after a provider failure or abandoned in-flight request, reserves one quota event; completed replays and requests rejected as already in progress do not. Thus the five-per-minute limit also bounds attempts made with a single idempotency key.

Errors use a JSON `error` code. Absent or malformed session tokens return `401 unauthorized`; unknown valid-format tokens return `401 unknown_session`; quota limits return `429 quota_exceeded` with `Retry-After`; provider, database, and service failures return `503 service_unavailable`. Invalid input returns `400`, oversized bodies return `413`, and an in-flight duplicate, out-of-order assertion, or conflicting idempotency key returns `409`.

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

`OPENAI_API_KEY` is read only by the server process and is never placed in the app bundle. Do not put real keys in shell history, tracked files, or this example. The listener defaults to `127.0.0.1:8787`; the database defaults to `craftberry-generation.sqlite` in the current directory. Keep the database on a durable local volume. SQLite WAL is intended for one host and must not be shared over NFS or used by multiple replicas. Startup takes an exclusive process-lifetime lock at `<database path>.lock` before opening SQLite and refuses a second server for the same database.

`APP_ATTEST_ALLOWED_BUNDLE_VERSIONS` must list each accepted app build. Attestations without bundle-version metadata are rejected when this list is configured unless it also includes the explicit `legacy-no-bundle-version` token. Assertions from real devices carry plain 37-byte authenticator data with no extension map, so the list is not applied to them; the build was checked at attestation.

## Staging and release setup still required

- Register the app's App ID in the Apple Developer account and enable App Attest. Set `APP_ATTEST_APP_ID` to the exact registered App ID (`prefix.bundle-id`); the prefix is not always the Team ID.
- Provision the iOS app with App Attest. Release builds use the `production` entitlement. Debug builds do not use App Attest and carry no entitlement, so they sign without the capability. A real device, a valid signing profile, and Apple service access are needed to test enrollment end to end.
- Configure `CRAFTBERRY_BACKEND_BASE_URL` in the app's release build settings to the actual HTTPS service origin. No deployed URL is configured in this repository.
- Run the service on a managed macOS host with a persistent encrypted volume and backups for the SQLite file. Place it behind a trusted TLS reverse proxy, configure request-size and connection limits, and rate-limit unauthenticated challenge requests. Do not expose the listener's plain HTTP port directly to the Internet.
- The executable sets a restrictive process umask before creating the SQLite database. Keep its parent directory private as well, and include the WAL/SHM files in the same protected volume and backup policy.
- Supply the provider key through the host's secret manager as `OPENAI_API_KEY`, and set `APP_ATTEST_APP_ID`, `APP_ATTEST_ENVIRONMENT`, and the explicitly allowed `APP_ATTEST_ALLOWED_BUNDLE_VERSIONS` there. Use separate development and production databases and App Attest environments.
- Configure monitoring, secret rotation, database retention/backup, and a recovery process for session revocation. Session tokens are random 256-bit values; the database stores only their SHA-256 digests. This slice does not include a user account system, remote token revocation endpoint, or multi-host quota store.

If a provider call succeeds but SQLite cannot persist its validated intent, the service marks the reservation retryable when possible and returns `503`. A later request with the same key can call the provider again; provider execution is therefore at least once across a result-persistence failure. The client’s in-memory pending operation preserves the idempotency key but cannot recover a result that SQLite never committed. Preventing this duplicate provider call would require provider-side idempotency or durable result storage.

The service verifies the enrollment receipt's CMS signature and certificate chain to the bundled Apple Root CA G3, then checks its App ID, attested certificate, challenge hash, `ATTEST` type, and five-minute creation-time window before storing it with the key. It does not submit receipts to Apple's fraud-risk API or consume the returned device risk metric. Obtaining a fraud metric also requires an APNs-style JWT signing key with DeviceCheck enabled, plus separate development and production receipt handling; no account credentials are present here. Apple's server-validation guide describes the receipt checks and later assertions, while the fraud-risk guide documents the authenticated `attestationData` call. See [Apple's server validation guide](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server), [app integrity guide](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity), and [fraud-risk guide](https://developer.apple.com/documentation/devicecheck/assessing-fraud-risk).

The runnable host is intentionally macOS-only today. Certificate-chain trust uses Apple's `Security` framework; the request assertion uses CryptoKit. A Linux host adapter is feasible, but it needs a separately packaged service core and maintained portable cryptography: Swift Crypto provides a substantial CryptoKit-compatible API for Linux, and OpenSSL provides explicit X.509 chain-verification APIs. This is an implementation assessment, not a tested adapter; it would need valid and invalid chain fixtures, no-network trust evaluation against the pinned Apple root, and parity tests for assertion signatures before use. Do not replace the current validation with shelling out to a system `openssl` binary or with an unverified trust callback. See [Apple Swift Crypto](https://github.com/apple/swift-crypto) and [OpenSSL certificate verification](https://docs.openssl.org/3.5/man3/X509_verify_cert/).

## Cloudflare Worker deployment

`server/` holds a TypeScript port of the same service for Cloudflare Workers. The HTTP contract (routes, headers, status codes, error codes, quota defaults of 5 per minute, 10 per hour and 30 per day) is unchanged, so the iOS client needs no change beyond `CRAFTBERRY_BACKEND_BASE_URL`. `GET /health` returns `{"ok":true,"configured":<bool>}` for monitoring.

- State lives in one SQLite-backed Durable Object (`GenerationStore`). Each store method runs without awaits, so reservations, counter updates and challenge consumption are atomic, as `BEGIN IMMEDIATE` plus the process lock were for the Swift store. An in-flight generation older than two minutes is treated as abandoned and may be retried (it spends a new quota event).
- The unauthenticated challenge endpoint is rate-limited to 30 requests per minute per client address (only a short hash of the address is stored) and answers `429 quota_exceeded`. `/v1/session/enroll` is limited to 10 attempts per minute per client address, and a failed attestation burns its challenge. Request bodies are size-limited while streaming, so a missing `Content-Length` does not bypass the limit.
- `cloudflare.config.ts` defines two modes. `staging` deploys `craftberry-generation-staging` with the `development` App Attest environment. `production` deploys `craftberry-generation-production` with `production`. Each Worker has its own Durable Object namespace and its own secrets.
- `OPENAI_API_KEY` is not declared in `cloudflare.config.ts`, so a deploy never writes or overwrites it (`cf deploy` also keeps existing secrets). If `APP_ATTEST_ALLOWED_BUNDLE_VERSIONS` is empty the Worker answers `503 service_not_configured`, like the Swift server refusing to start.
- Until `OPENAI_API_KEY` is set, authenticated generation returns `503 service_not_configured` and spends no quota. Set it once per environment. Read the key without echo so it never enters shell history or the repo:

```sh
read -rs OPENAI_KEY
cf workers secrets update OPENAI_API_KEY --worker craftberry-generation-staging --text "$OPENAI_KEY"
cf workers secrets update OPENAI_API_KEY --worker craftberry-generation-production --text "$OPENAI_KEY"
unset OPENAI_KEY
```

- `server/scripts/smoke.sh <base-url>` checks health, challenge issue and that unattested generation is rejected.
- `.github/workflows/server.yml` builds, type-checks, tests and dry-runs both modes on pull requests, deploys staging on push to `main`, and deploys production only by manual dispatch from `main` (the dispatch default is `staging`). It needs repository secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
- The Worker does not run the full Swift project validator on the model output. It checks the intent envelope and relies on the strict JSON schema sent to OpenAI (generated from the Swift client). The iOS client still assembles and validates the intent locally.
- Receipt-to-fraud-risk handling and the other limits listed above are unchanged.
