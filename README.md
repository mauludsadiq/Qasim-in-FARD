# Qasim in FARD

Deterministic, verifiable financial state engine built in FARD.

---

## Overview

Qasim is a cryptographically anchored financial computation system.

It ingests signed transactions and multi-source price feeds, computes consensus prices, derives positions and NAV, and produces a fully reproducible state digest.

Every output is traceable back to:
- canonical payloads
- source data
- cryptographic hashes
- signatures

No hidden state. No ambiguity. No trust assumptions.

---

## Core Properties

### Deterministic
Same inputs → same outputs → same digests

### Verifiable
All data is:
- hash-addressed
- signature-backed
- replayable

### Multi-source consensus
Prices are aggregated across sources:
- mean (consensus)
- variance computed
- outliers detected
- median is not computed (no sort in stdlib) — returned as null

### Replayable state
Entire system can be recomputed from:
- fills
- price claims

---

## Architecture

### Modular Structure

- main.fard                  -> composition root, DB schema, ctx wiring, chain witnessing, server startup
- packages/qasim_http        -> full routing table, all request handlers, response shaping
- packages/qasim_prices      -> price loading, staleness filtering, aggregation, consensus
- packages/qasim_state       -> positions, NAV, state receipts, risk state
- packages/qasim_scenarios   -> scenario evaluation, shock maps, named scenario library
- packages/qasim_crypto      -> Ed25519 chain signing
- packages/qasim_objects     -> canonical signed object constructors

All routing and handler logic lives in qasim_http. main.fard wires dependencies
into a ctx record and passes it to qasim_http.handle on every request.

---

## Endpoints

### Ingest

POST /finance/ingest/tx
POST /finance/ingest/cash
POST /finance/ingest/order
POST /finance/ingest/fill
POST /finance/price/claim
POST /finance/live/price
POST /finance/replay

All mutating endpoints require a non-empty request body.
Signed payloads are verified via Ed25519 before storage.
Records are immutable once written (INSERT OR IGNORE — first write wins).
Future-dated ts_unix values are rejected at ingest.

### Query

GET /finance/position/<account>
GET /finance/export/<account>
GET /finance/price/aggregate/<symbol>
GET /finance/state_at/<account>/<ts_unix>
GET /finance/export_at/<account>/<ts_unix>
GET /finance/state_payload/<account>/<ts_unix>
GET /finance/scenario_at/<account>/<ts_unix>/<scenario>
GET /finance/chain/verify
GET /health

---

## Storage

SQLite tables (all append-only via INSERT OR IGNORE):

- tx              — signed transaction records
- fills           — signed fill records (used for position computation)
- orders          — signed order records
- cash_objects    — signed cash records
- price_claims    — signed multi-source price records
- object_store    — unified object index by type
- receipt_log     — append-only chain of request/response/state digests

Positions and NAV are computed from fills, not tx.
tx records are stored but not used in valuation.

---

## Price Staleness

Qasim enforces an explicit freshness constraint on all price data.

Parameter: MAX_PRICE_AGE = 300 seconds

A price is valid at time t only if:
- ts_unix ≤ t
- (t - ts_unix) ≤ MAX_PRICE_AGE

Stale prices are excluded from valuation. Affected positions show price = null
and are excluded from NAV. This applies to all endpoints including the
non-time-indexed /finance/position/ and /finance/export/ endpoints,
which use the server wall clock as the cutoff.

Future-dated prices (ts_unix > now) are rejected at ingest.

---

## Canonical State Model

state_digest = SHA256(
  account,
  as_of_ts,
  fill_digests,
  cash_digests,
  price_digests,
  positions,
  nav,
  risk_state
)

Where:

risk_state = deterministic transform of positions including:
- gross_exposure
- net_exposure
- long_exposure
- short_exposure
- leverage
- concentration

Live position queries pass as_of_ts = null. State digests from
/finance/position/ are not time-anchored. Use /finance/state_at/
for time-indexed, reproducible digests.

---

## Time-Indexed State

State is a pure function:

  state(t) = f(fills ≤ t, prices ≤ t)

All _at endpoints accept a ts_unix cutoff and use only data at or before t.
No forward-looking data is ever used. Digests include as_of_ts.

Endpoints:
- GET /finance/state_at/<account>/<ts_unix>
- GET /finance/export_at/<account>/<ts_unix>
- GET /finance/state_payload/<account>/<ts_unix>
- GET /finance/scenario_at/<account>/<ts_unix>/<scenario>

Replay also accepts an optional as_of_ts field to constrain to a historical cutoff.

---

## Scenario System

Scenarios are deterministic transforms applied to base state.

### Types

1. Instrument shock maps: AAPL:-0.2,MSFT:-0.1
2. Named scenarios: equity_down_10, equity_up_10, market_crash_20, tech_selloff, bull_case

### Output

- scenario
- scenario_version
- shock_spec
- shocked_positions
- shocked_nav
- pnl
- scenario_digest

scenario_digest = SHA256(account, as_of_ts, scenario, scenario_version,
                         shock_spec, shocked_positions, shocked_nav, pnl)

Scenarios do not modify base state_digest.

---

## Receipt Chain

Every request is recorded in an append-only receipt_log.

Each entry stores:
- req_digest    — SHA256 of canonical request (path + body)
- res_digest    — SHA256 of canonical response (status + headers + body)
- state_digest  — extracted from response body if present
- chain_digest  — SHA256 of (prev_chain_digest, req_digest, res_digest, state_digest)
- payload_json  — the pre-image used to compute chain_digest

Chain rule:
  chain_digest_n = SHA256(chain_digest_{n-1}, request, response, state)

Genesis value: "GENESIS"

Chain integrity can be verified at any time:
  GET /finance/chain/verify

This endpoint walks the full receipt_log, recomputes each chain_digest
from its stored payload_json, and verifies the prev_chain_digest linkage.
Returns { valid, checked, head } or { valid: false, failed_at, reason }.

---

## Cryptographic Signing

### Chain signing
Qasim signs the chain head using Ed25519.
The signing key is loaded from the environment at startup — never hardcoded.

Required:
  export QASIM_CHAIN_SECRET_HEX=$(openssl rand -hex 32)

Response headers:
- X-Qasim-Chain-Digest
- X-Qasim-Chain-Signature
- X-Qasim-Chain-Public-Key
- X-Qasim-Request-Digest
- X-Qasim-Response-Digest

### Payload signing
All ingest payloads are verified via Ed25519 before storage.
Use pk_hex = "DEV" to bypass verification in development.

### Live feed signing
Live price ingestion uses HMAC-SHA256 (symmetric). The signing_secret_hex
is provided per-request. This is weaker than asymmetric signing — the
verifier must hold the secret.

---

## Limitations

- Mean consensus only (no weighted mean, no trimmed mean — no sort in stdlib)
- Median not computable — returned as null in aggregate response
- No URL decoding (e.g. %2F in path parameters)
- HMAC for live feed signing (not asymmetric)
- Limited asset coverage
- Live /finance/position/ digest not time-anchored (as_of_ts: null)

---

## Future Extensions

- Weighted consensus
- Trimmed mean
- Signature verification on read
- URL decoding
- Multi-asset support
- Matching / clearing engine
- FARD receipts per request
- Time-anchored live position digest

---

## Running

Generate a signing key and start the server:

  export QASIM_CHAIN_SECRET_HEX=$(openssl rand -hex 32)
  ~/FARD/target/release/fardrun run --program main.fard --out /tmp/qasim

Server: http://0.0.0.0:9801

The signing key must be preserved across restarts to maintain chain
signature continuity. Store it in a secrets manager for production use.

---

## Philosophy

Qasim follows FARD principles:

- execution produces artifacts
- artifacts are cryptographically anchored
- computation is deterministic
- verification is first-class

This is not an API.

This is a verifiable financial system.
