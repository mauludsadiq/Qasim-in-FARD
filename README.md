# Qasim in FARD

Deterministic, verifiable financial state engine built in FARD.

---

## What is Qasim?

Qasim is a cryptographically anchored financial computation system. It ingests
signed transactions, fills, instruments, and multi-source price feeds, computes
recency-weighted consensus prices, derives asset-class-aware positions and NAV,
and produces a fully reproducible state digest.

Every output is traceable back to canonical payloads, source data, cryptographic
hashes, and signatures. No hidden state. No ambiguity. No trust assumptions.

The core guarantee: given the same inputs, Qasim will always produce the same
state digest. Any third party can replay the full computation from exported data
and arrive at an identical result.

---

## Quickstart

Generate a signing key and start the server:

  export QASIM_CHAIN_SECRET_HEX=$(openssl rand -hex 32)
  fardrun run --program main.fard --out /tmp/qasim

Server listens on http://0.0.0.0:9801

  curl http://0.0.0.0:9801/health
  {"status":"ok"}

QASIM_CHAIN_SECRET_HEX must be set before starting. The server fails fast if
it is missing. Preserve the key across restarts — store it in a secrets manager
for production use.

---

## Walkthrough

### 1. Register an instrument

  curl -X POST http://0.0.0.0:9801/finance/ingest/instrument \
    -H "Content-Type: application/json" \
    -d '{"payload_json":"{\"instrument_id\":\"AAPL\",\"asset_class\":\"equity\",\"symbol\":\"AAPL\",\"currency\":\"USD\",\"venue\":\"NASDAQ\",\"multiplier\":1,\"expiry_ts_unix\":0}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

### 2. Ingest a fill

  curl -X POST http://0.0.0.0:9801/finance/ingest/fill \
    -H "Content-Type: application/json" \
    -d '{"payload_json":"{\"fill_id\":\"F1\",\"order_id\":\"O1\",\"account\":\"ACCT-123\",\"instrument\":\"AAPL\",\"side\":\"buy\",\"qty\":6,\"price\":171,\"ts_unix\":1731000202}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

### 3. Ingest cash

  curl -X POST http://0.0.0.0:9801/finance/ingest/cash \
    -H "Content-Type: application/json" \
    -d '{"payload_json":"{\"account\":\"ACCT-123\",\"currency\":\"USD\",\"amount\":1000,\"ts_unix\":1731000100}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

### 4. Submit a price claim

  curl -X POST http://0.0.0.0:9801/finance/price/claim \
    -H "Content-Type: application/json" \
    -d '{"payload_json":"{\"symbol\":\"AAPL/USD\",\"mid\":171,\"venue\":\"NASDAQ\",\"ts_unix\":1731000500}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

### 5. Query position and NAV

  curl http://0.0.0.0:9801/finance/position/ACCT-123

Returns positions with qty, price, value, asset_class, cash_balance, nav,
risk_state, and state_digest.

### 6. Aggregate prices across sources

  curl "http://0.0.0.0:9801/finance/price/aggregate/AAPL%2FUSD"
  {"mean":171,"median":null,"weighted_mean":171,"variance":0,"outliers":[],"sources":[...]}

### 7. Verify chain integrity

  curl http://0.0.0.0:9801/finance/chain/verify
  {"valid":true,"checked":12,"head":"sha256:..."}

### 8. Export full replay package

  curl http://0.0.0.0:9801/finance/export/ACCT-123

Returns all fills, cash, prices, positions, NAV, risk state, and state digest.
Any party can replay this using POST /finance/replay and arrive at the same
state_digest.

---

## Core Properties

### Deterministic
Same inputs produce same outputs and same digests. No randomness, no wall-clock
dependency in state computation.

### Verifiable
All data is hash-addressed, signature-backed, and replayable. The receipt chain
records every request and response in an append-only tamper-evident log.

### Asset-class-aware valuation

  equity        qty x price x multiplier
  future        qty x price x multiplier
  option        qty x price x multiplier
  fixed_income  qty x (price / 100) x multiplier   (clean price convention)
  fx            qty x price

Unregistered instruments default to equity with multiplier 1.

### Recency-weighted consensus

  weight = 300 - (now - ts_unix)   minimum: 1
  weighted_mean = sum(weight x mid) / sum(weight)

The most recent source gets maximum weight (300). Staleness limit is 300s.

---

## Endpoints

### Ingest

  POST /finance/ingest/instrument    Register instrument with asset class
  POST /finance/ingest/tx            Record a transaction
  POST /finance/ingest/cash          Record a cash balance
  POST /finance/ingest/order         Record an order
  POST /finance/ingest/fill          Record an execution fill
  POST /finance/price/claim          Submit a signed price
  POST /finance/live/price           Fetch and sign a live price feed
  POST /finance/replay               Replay state from supplied data

All mutating endpoints require a non-empty body. Ed25519 signatures are verified
before storage. Records are immutable — first write wins (INSERT OR IGNORE).
Future-dated ts_unix values are rejected. URL-encoded path parameters are decoded.

### Query

  GET /finance/position/<account>                      Live position and NAV
  GET /finance/export/<account>                        Full replay package
  GET /finance/price/aggregate/<symbol>                Multi-source consensus
  GET /finance/state_at/<account>/<ts_unix>            Time-indexed state
  GET /finance/export_at/<account>/<ts_unix>           Time-indexed export
  GET /finance/state_payload/<account>/<ts_unix>       Raw state digest payload
  GET /finance/scenario_at/<account>/<ts_unix>/<s>     Scenario evaluation
  GET /finance/chain/verify                            Chain integrity check
  GET /health                                          Server health

---

## Canonical State Model

  state_digest = SHA256(
    account, as_of_ts,
    fill_digests, cash_digests, price_digests,
    positions, nav, risk_state
  )

risk_state includes: gross_exposure, net_exposure, long_exposure,
short_exposure, leverage (gross/nav), concentration (max position weight).

Live /finance/position/ passes as_of_ts = null and is not time-anchored.
Use /finance/state_at/ for reproducible, time-indexed digests.

---

## Time-Indexed State

  state(t) = f(fills <= t, prices <= t)

All _at endpoints accept a ts_unix cutoff. Only data at or before t is used.
No forward-looking data is ever used. Digests include as_of_ts.

---

## Scenario Analysis

Scenarios apply deterministic shocks to base state without modifying it.

Instrument shock map:  AAPL:-0.2,MSFT:-0.1
Named scenarios:       equity_down_10, equity_up_10, market_crash_20,
                       tech_selloff, bull_case

Each scenario returns shocked_positions, shocked_nav, pnl, and a
scenario_digest — a canonical hash of all scenario inputs and outputs.

---

## Receipt Chain

Every request is recorded in receipt_log:

  chain_digest_n = SHA256(chain_digest_{n-1}, req_digest, res_digest, state_digest)

Genesis: "GENESIS"

Response headers per request:
  X-Qasim-Chain-Digest       current chain head
  X-Qasim-Chain-Signature    Ed25519 signature over chain head
  X-Qasim-Chain-Public-Key   verifying public key
  X-Qasim-Request-Digest     SHA256 of canonical request
  X-Qasim-Response-Digest    SHA256 of canonical response

GET /finance/chain/verify walks the full log, recomputes every digest from
stored pre-images, and verifies linkage. Returns {valid, checked, head}.

---

## Cryptographic Signing

Chain signing: Ed25519. Key from QASIM_CHAIN_SECRET_HEX at startup.

Payload signing: all ingest payloads carry issuer_pk_hex and sig_b64,
verified via Ed25519 before storage. Use pk_hex = "DEV" in development.

Live feed signing: POST /finance/live/price fetches an external URL, builds
a canonical receipt, and signs it with the caller's Ed25519 key
(issuer_secret_hex). Verifiable against issuer_pk_hex with no shared secret.

---

## Architecture

  main.fard
    DB schema, ctx wiring, chain witnessing, net.serve

  packages/
    qasim_http/      routing, all handlers, request/response shaping
    qasim_prices/    price loading, staleness, aggregation, weighted consensus
    qasim_state/     positions, NAV, risk state, asset-class valuation
    qasim_scenarios/ scenario evaluation, shock maps, named library
    qasim_crypto/    Ed25519 chain signing
    qasim_objects/   canonical signed object constructors

All routing lives in qasim_http. main.fard wires dependencies into a ctx
record and delegates every request to qasim_http.handle(req, ctx).

---

## Storage

SQLite tables (all append-only via INSERT OR IGNORE):

  tx              Signed transaction records
  fills           Signed fill records (source of position truth)
  orders          Signed order records
  cash_objects    Signed cash records
  price_claims    Signed multi-source price records
  object_store    Unified index by object type
  receipt_log     Append-only chain of request/response digests

Positions and NAV are computed from fills, not tx.

---

## Test Suite

  fardrun test --program tests/test_qasim_objects.fard        9 tests
  fardrun test --program tests/test_qasim_objects_model.fard  12 tests
  fardrun test --program tests/test_qasim_prices.fard         10 tests
  fardrun test --program tests/test_qasim_state.fard          11 tests
  42 tests total, all passing

---

## Limitations

- No trimmed mean (no sort in FARD stdlib)
- Median not computable — returned as null
- Live /finance/position/ digest not time-anchored (as_of_ts: null)
- Instrument metadata fetched per-request (no in-memory cache)
- No multi-currency NAV

---

## Future Extensions

- Trimmed mean consensus
- Signature verification on read
- Multi-currency NAV with FX conversion
- Corporate action processing (splits, dividends)
- Matching and clearing engine
- FARD execution receipts per request
- Time-anchored live position digest
- Weighted scenario library

---

## Philosophy

Qasim follows FARD principles:

- execution produces artifacts
- artifacts are cryptographically anchored
- computation is deterministic
- verification is first-class

This is not an API. This is a verifiable financial system.
