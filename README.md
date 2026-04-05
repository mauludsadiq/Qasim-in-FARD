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
- mean (current)
- variance computed
- outliers detected

### Replayable state
Entire system can be recomputed from:
- transactions
- price claims

---

## Architecture

### 1. Ingestion

#### Transactions
POST /finance/ingest/tx

Requires:
- payload_json
- issuer_pk_hex
- sig_b64

Verified via Ed25519

---

#### Price claims
POST /finance/price/claim

Signed payloads stored as immutable records

---

#### Live price ingestion
POST /finance/live/price

Inputs:
- symbol
- venue
- url
- feed_type
- issuer_pk_hex
- signing_secret_hex

Process:
1. Fetch external data
2. Adapt into canonical format
3. Build receipt
4. Hash receipt
5. Sign receipt (HMAC)
6. Store as price_claim

---

### 2. Storage

SQLite tables:

tx
- signed transaction records

price_claims
- signed multi-source price records

---

### 3. Aggregation

GET /finance/price/aggregate/<symbol>

Returns:
- mean (consensus)
- variance
- outliers
- sources

Consensus rule:
mean-based (deterministic, no sorting dependency)

---

### 4. Positions & NAV

GET /finance/position/<account>

- aggregates transactions
- applies consensus price
- computes:
  - positions
  - NAV
  - state digest

---

### 5. Export

GET /finance/export/<account>

Returns:
- transactions
- price claims
- positions
- NAV
- state digest

Complete replay package

---

### 6. Replay

POST /finance/replay

Input:
- txs
- prices

Output:
- positions
- NAV
- state digest

---

## State Commitment

State = SHA256(
  account,
  tx_digests,
  price_digests,
  positions,
  nav
)

Guarantees:
- reproducibility
- tamper detection
- auditability

---

## Consensus Model

For each symbol:

1. Collect price claims
2. Compute:
   - mean
   - variance
3. Detect outliers:
   (x - mean)^2 > 4 × variance

Consensus price = mean

---

## Example Flow

1. Ingest transaction
POST /finance/ingest/tx

2. Ingest prices
POST /finance/live/price

3. Query aggregate
GET /finance/price/aggregate/AAPL/USD

4. Compute NAV
GET /finance/position/ACCT-123

5. Export state
GET /finance/export/ACCT-123

---

## Key Guarantees

- No mutable hidden state
- No unverifiable data
- Full replayability
- Deterministic outputs

---

## Limitations

- Mean used instead of median (no sort in stdlib)
- No weighting across sources
- No URL decoding (e.g. %2F)
- HMAC signing for live feeds (not asymmetric)

---

## Future Extensions

- Weighted consensus
- Trimmed mean
- Signature verification on read
- URL decoding
- Multi-asset support
- Matching / clearing engine
- FARD receipts per request

---

## Running

Start server:

~/FARD/target/release/fardrun run --program main.fard --out /tmp/qasim

Server:

http://0.0.0.0:9801

---

## Philosophy

Qasim follows FARD principles:

- execution produces artifacts
- artifacts are cryptographically anchored
- computation is deterministic
- verification is first-class

This is not an API.

This is a verifiable financial system.

---

## Time-Indexed State (NEW)

### Price Staleness (NEW)

Qasim enforces an explicit freshness constraint on price data.

#### Parameter

MAX_PRICE_AGE = 300  (seconds)

#### Rule

A price is considered valid at time t only if:

- ts_unix ≤ t
- (t - ts_unix) ≤ MAX_PRICE_AGE

Otherwise the price is discarded.

#### Effect

- Stale prices are not used in valuation
- Positions remain, but value becomes null
- NAV excludes assets with stale pricing

#### Example

At time t = 1731000500

Latest price ts = 1731000120

Δ = 380 > 300 → price is stale

Result:

qty = 6
price = null
value = null
nav = 0

This ensures economic correctness and prevents outdated data from influencing state.

---

## Time-Indexed State (NEW)

Qasim now supports deterministic state evaluation at any time t.

### Endpoint

GET /finance/state_at/<account>/<ts_unix>

### Behavior

State is computed using only data ≤ t:

- tx where ts_unix ≤ t
- price_claims where ts_unix ≤ t

No forward-looking data is ever used.

### Properties

- Time-consistent valuation
- No lookahead bias
- Missing prices remain null (no implicit fill)
- State digest includes as_of_ts

### Example

Before price arrival:

qty = 10
price = null
nav = 0

After price + second tx:

qty = 6
price = 171
nav = 1026

### Export at time

GET /finance/export_at/<account>/<ts_unix>

Returns full replayable state at time t.

### Replay with time

POST /finance/replay

Optional field:

as_of_ts

This constrains replay to historical cutoff.

### Guarantee

State is a pure function:

state(t) = f(tx≤t, price≤t)

Digest changes with time.

---

