# Qasim in FARD

Deterministic, cryptographically verifiable financial state engine built in FARD.

-----

## What is Qasim?

Qasim is a cryptographically anchored financial computation system. It ingests signed fills, instruments, corporate actions, and multi-source price feeds, computes recency-weighted consensus prices, derives asset-class-aware positions and unified NAV across public, private, and derivatives books, and produces a fully reproducible state digest.

Every output is traceable back to canonical payloads, cryptographic hashes, and Ed25519 signatures. No hidden state. No ambiguity. No trust assumptions.

**The core guarantee:** given the same inputs, Qasim always produces the same state digest. Any third party can replay the full computation from exported data and arrive at an identical result.

-----

## Quickstart

```bash
git clone https://github.com/mauludsadiq/Qasim-in-FARD.git
cd Qasim-in-FARD

export QASIM_CHAIN_SECRET_HEX=$(openssl rand -hex 32)
export QASIM_ADMIN_KEY_HASH=$(echo -n "apikey:my-dev-key" | sha256sum | awk '{print "sha256:"$1}')
fardrun run --program main.fard --out /tmp/qasim
```

Server listens on **http://0.0.0.0:9801**. Your admin API key is `my-dev-key`.

```bash
curl http://0.0.0.0:9801/health
# {"status":"ok"}
```

`QASIM_CHAIN_SECRET_HEX` anchors the receipt chain — preserve it across restarts and store in a secrets manager for production. `QASIM_ADMIN_KEY_HASH` is `SHA256("apikey:<key>")` and bootstraps RBAC.

**Docker:**

```bash
docker compose up
```

**Kubernetes (Helm):**

```bash
ADMIN_KEY=$(openssl rand -hex 32)
ADMIN_HASH=$(echo -n "apikey:${ADMIN_KEY}" | sha256sum | awk '{print "sha256:"$1}')
helm install qasim ./helm/qasim \
  --set secret.chainSecretHex=$(openssl rand -hex 32) \
  --set secret.adminKeyHash="${ADMIN_HASH}"
echo "Admin key: ${ADMIN_KEY}"
```

-----

## Walkthrough

### 1. Create an API key

```bash
curl -X POST http://0.0.0.0:9801/admin/api_keys \
  -H "Content-Type: application/json" \
  -H "X-API-Key: my-dev-key" \
  -d '{"label":"trader-1","role":"trader","key":"trader-secret"}'
```

Roles: `admin` | `trader` | `risk` | `readonly`. All write endpoints require `-H "X-API-Key: <key>"`.

### 2. Register instruments

```bash
# Equity
curl -X POST http://0.0.0.0:9801/finance/ingest/instrument \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"payload_json":"{\"instrument_id\":\"AAPL\",\"asset_class\":\"equity\",\"symbol\":\"AAPL\",\"currency\":\"USD\",\"venue\":\"NASDAQ\",\"multiplier\":1,\"expiry_ts_unix\":0}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

# Bond (UST 10Y: 4.5% coupon, semi-annual, YTM 4.75%)
curl -X POST http://0.0.0.0:9801/finance/ingest/instrument \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"payload_json":"{\"instrument_id\":\"UST10Y\",\"asset_class\":\"fixed_income\",\"symbol\":\"UST10Y\",\"currency\":\"USD\",\"venue\":\"OTC\",\"multiplier\":1000,\"expiry_ts_unix\":1778000000,\"coupon_rate\":0.045,\"face_value\":100,\"coupon_frequency\":2,\"ytm\":0.0475}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

# Futures (E-mini S&P 500, multiplier 50)
curl -X POST http://0.0.0.0:9801/finance/ingest/instrument \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"payload_json":"{\"instrument_id\":\"ESZ24\",\"asset_class\":\"future\",\"symbol\":\"ES\",\"currency\":\"USD\",\"venue\":\"CME\",\"multiplier\":50,\"expiry_ts_unix\":1778000000}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'
```

### 3. Ingest cash and fills

```bash
NOW=$(date +%s)

curl -X POST http://0.0.0.0:9801/finance/ingest/cash \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d "{\"payload_json\":\"{\\\"account\\\":\\\"ACCT-123\\\",\\\"currency\\\":\\\"USD\\\",\\\"amount\\\":500000,\\\"ts_unix\\\":$NOW}\",\"issuer_pk_hex\":\"DEV\",\"sig_b64\":\"DEV\"}"

curl -X POST http://0.0.0.0:9801/finance/ingest/fill \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d "{\"payload_json\":\"{\\\"fill_id\\\":\\\"F1\\\",\\\"order_id\\\":\\\"O1\\\",\\\"account\\\":\\\"ACCT-123\\\",\\\"instrument\\\":\\\"AAPL\\\",\\\"side\\\":\\\"buy\\\",\\\"qty\\\":100,\\\"price\\\":170,\\\"ts_unix\\\":$NOW}\",\"issuer_pk_hex\":\"DEV\",\"sig_b64\":\"DEV\"}"
```

### 4. Submit a price

```bash
NOW=$(date +%s)

curl -X POST http://0.0.0.0:9801/finance/price/claim \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d "{\"payload_json\":\"{\\\"symbol\\\":\\\"AAPL/USD\\\",\\\"mid\\\":172,\\\"ts_unix\\\":$NOW}\",\"issuer_pk_hex\":\"DEV\",\"sig_b64\":\"DEV\"}"
```

### 5. Register a compliance rule

```bash
curl -X POST http://0.0.0.0:9801/finance/ingest/compliance_rule \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"payload_json":"{\"rule_id\":\"R1\",\"account\":\"ACCT-123\",\"rule_type\":\"max_position_size\",\"params\":{\"instrument\":\"AAPL\",\"max_value\":50000},\"severity\":\"hard\",\"effective_ts\":0,\"expiry_ts\":0}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'
```

### 6. Submit and match orders

```bash
NOW=$(date +%s)

curl -X POST http://0.0.0.0:9801/finance/ingest/order \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d "{\"payload_json\":\"{\\\"order_id\\\":\\\"O-BUY-1\\\",\\\"account\\\":\\\"ACCT-A\\\",\\\"instrument\\\":\\\"AAPL\\\",\\\"side\\\":\\\"buy\\\",\\\"qty\\\":100,\\\"order_type\\\":\\\"limit\\\",\\\"limit_price\\\":175,\\\"ts_unix\\\":$NOW}\",\"issuer_pk_hex\":\"DEV\",\"sig_b64\":\"DEV\"}"

curl -X POST http://0.0.0.0:9801/finance/match \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"instrument":"AAPL","compliance_mode":"block_on_hard","issuer_pk_hex":"DEV"}'
```

Returns `fills_generated`, `fills`, `blocked_matches`, and `blocked` (with breach reasons).

### 7. Query live position

```bash
curl http://0.0.0.0:9801/finance/position/ACCT-123
```

Response includes `verified`, `verification_digest`, `positions` (all asset classes with Greeks/DV01/MTM), `public_nav`, `private_nav`, `total_nav`, `futures` summary, `ir_risk` summary, `risk_state` (6 VaR methods), and `state_digest`.
> **Note on digests:** `/finance/position` is a live snapshot — `as_of_ts` is set to the current wall-clock time on every request, so `state_digest` changes each second even with identical underlying data. This is by design: every snapshot is uniquely time-anchored. For a reproducible digest, use the time-indexed endpoint:
>
> ```bash
> # Capture a timestamp from a live position call
> TS=$(curl -s http://0.0.0.0:9801/finance/position/ACCT-123 | python3 -c "import json,sys; print(json.load(sys.stdin)['as_of_ts'])")
>
> # These two calls will always return identical state_digest
> curl -s http://0.0.0.0:9801/finance/state_at/ACCT-123/$TS
> curl -s http://0.0.0.0:9801/finance/state_at/ACCT-123/$TS
> ```


### 8. Check compliance

```bash
curl http://0.0.0.0:9801/finance/compliance/ACCT-123
```

Returns `passed`, `results` (per rule), `breach_count`, `hard_breach_count`, each breach with `suggested_action`.

### 9. Liquidity forecast

```bash
curl http://0.0.0.0:9801/finance/liquidity/ACCT-123
```

Returns `current_cash`, `margin_buffer`, `liquidity_score` (0-100), `warnings`, and `projected` cash flows at 30, 90, and 365 days.

### 10. Audit export

```bash
curl http://0.0.0.0:9801/finance/audit/export/ACCT-123
```

Returns a single tamper-evident bundle with `audit_digest` (SHA256 of the entire bundle). Includes positions, risk snapshot, compliance report, 10 stress scenarios, attribution, and receipt chain digest. Any field alteration invalidates `audit_digest`.

### 11. Verify chain integrity

```bash
curl http://0.0.0.0:9801/finance/chain/verify
# {"valid":true,"checked":12,"head":"sha256:..."}
```

### 12. Export replay package

```bash
curl http://0.0.0.0:9801/finance/export/ACCT-123
```

Returns all fills, cash, prices, positions, NAV, and `state_digest`. Any party can replay this and arrive at an identical digest.

-----

## Asset Classes

Qasim handles six asset classes with appropriate valuation and risk measures for each.

|Asset class |Value                         |Risk measures                              |
|------------|------------------------------|-------------------------------------------|
|equity      |qty × price × multiplier      |Parametric VaR, Historical VaR, ES         |
|fixed_income|qty × (price/100) × multiplier|DV01, Macaulay/Modified Duration, Convexity|
|option      |qty × price × multiplier      |Black-Scholes Greeks (Δ, Γ, ν, θ, ρ)       |
|future      |initial_margin (5% default)   |MTM P&L, Notional, Variation/Initial Margin|
|fx          |qty × price                   |VaR, multi-currency NAV                    |
|private     |DCF at 8% discount rate       |Illiquidity %, Capital Call Exposure       |

Unregistered instruments default to equity with multiplier 1.

### Futures

Futures value = margin posted (not notional). Additional position fields:

```
notional          qty × price × multiplier
entry_price       VWAP of buy fills
mtm_pnl           qty × (current_price - entry_price) × multiplier
variation_margin  max(mtm_pnl, 0)
initial_margin    abs(qty) × price × multiplier × initial_margin_rate
expiry_ts         from instrument metadata
```

MTM P&L is included in `total_nav`. Portfolio futures summary in `/finance/position`:

```json
"futures": {
  "count": 1,
  "total_notional": 17675000,
  "total_mtm_pnl": 175000,
  "total_variation_margin": 175000,
  "total_initial_margin": 883750
}
```

### Fixed Income

Bond registration requires coupon and yield fields:

```json
{
  "instrument_id": "UST10Y",
  "asset_class": "fixed_income",
  "coupon_rate": 0.045,
  "face_value": 100,
  "coupon_frequency": 2,
  "ytm": 0.0475,
  "expiry_ts_unix": 1778000000
}
```

Discounting: `DF = (1 + ytm/m)^(-t×m)` (discrete semi-annual). Each fixed income position includes:

```json
"ir_risk": {
  "macaulay_duration": 7.81,
  "modified_duration": 7.63,
  "convexity": 69.5,
  "dv01": -524.21,
  "ytm": 0.0475,
  "coupon_rate": 0.045,
  "face_value": 100,
  "clean_price": 98.10
}
```

Portfolio IR summary in `/finance/position`:

```json
"ir_risk": {
  "fi_count": 1,
  "total_dv01": -524.21,
  "portfolio_mod_duration": 7.63
}
```

-----

## Risk Suite

Six VaR methods computed on every `/finance/position` call.

**Parametric VaR** — from realized volatility:

```
var_95 = |value| × stddev(returns) × 1.645
var_99 = |value| × stddev(returns) × 2.326
```

**Historical VaR** — exact P&L distribution, 252-day lookback. Requires n ≥ 10.

**Expected Shortfall (CVaR)** — mean loss beyond VaR threshold. ES ≥ VaR always.

**Covariance VaR** — full Markowitz covariance matrix: `variance = w^T × Σ × w`. Shows diversification benefit vs additive VaR.

**Gaussian Cholesky MC** — 1000 correlated simulations, seed=42, fully reproducible. LCG + Box-Muller, Cholesky decomposition in pure FARD.

**Student-t Cholesky MC** — same as above but draws from t(ν=4). +24% VaR premium at 95%, +57% at 99%.

Illustrative results (mixed equity portfolio):

```
gaussian independent:   299    (uncorrelated baseline)
analytic covar:        1705    (correlation-aware)
gaussian cholesky:     1789    (MC correlated)
student-t cholesky:    2211    (+24% fat-tail premium at 95%)
student-t 99%:         3986    (+57% fat-tail premium at 99%)
```

Exposures are delta-adjusted for options: `unit_delta × spot × qty × multiplier`.

-----

## Compliance Rules Engine

18 rule types evaluated against live risk state including futures margins, private DCF NAV, VaR, ES, and Greeks.

```bash
curl -X POST http://0.0.0.0:9801/finance/ingest/compliance_rule \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"payload_json":"{\"rule_id\":\"R1\",\"account\":\"ACCT-123\",\"rule_type\":\"max_margin_utilization\",\"params\":{\"max_pct\":80},\"severity\":\"hard\",\"effective_ts\":0,\"expiry_ts\":0}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'
```

|Category |Rule types                                                                                                |
|---------|----------------------------------------------------------------------------------------------------------|
|Position |`max_position_size`, `max_position_qty`, `instrument_blacklist`                                           |
|Portfolio|`max_concentration`, `max_leverage`, `max_gross_exposure`, `max_asset_class_exposure`                     |
|Cash     |`min_cash_pct`                                                                                            |
|Greeks   |`max_delta_exposure`, `max_vega`                                                                          |
|VaR      |`max_portfolio_var_95`, `max_portfolio_var_99`, `max_portfolio_covar_var_95`, `max_portfolio_covar_var_99`|
|Tail Risk|`max_es_95`, `max_es_99`                                                                                  |
|Private  |`max_illiquid_pct`, `max_capital_call_exposure`                                                           |
|Futures  |`max_margin_utilization`                                                                                  |

Each breach includes a `suggested_action`. Rules with `account="*"` apply globally. `passed=true` only when zero hard breaches. Pre-trade compliance delta available via `POST /finance/pretrade`.

-----

## Authentication & RBAC

All write endpoints require an `X-API-Key` header. Read endpoints are open.

|Role    |Permissions                                                 |
|--------|------------------------------------------------------------|
|admin   |Full access: ingest, match, compliance rules, key management|
|trader  |Ingest + match + read                                       |
|risk    |Manage compliance rules + read                              |
|readonly|Read only                                                   |

```bash
# Create a key (admin only)
curl -X POST http://0.0.0.0:9801/admin/api_keys \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"label":"trader-desk","role":"trader","key":"my-trader-key"}'

# Create a key with expiry
curl -X POST http://0.0.0.0:9801/admin/api_keys \
  -H "X-API-Key: my-dev-key" \
  -H "Content-Type: application/json" \
  -d '{"label":"temp-key","role":"readonly","key":"temp-secret","expiry_ts":1778000000}'

# Revoke a key
curl -X DELETE http://0.0.0.0:9801/admin/api_keys/<key_hash> \
  -H "X-API-Key: my-dev-key"

# List all keys
curl http://0.0.0.0:9801/admin/api_keys \
  -H "X-API-Key: my-dev-key"
```

Raw keys are never stored — only `SHA256("apikey:<key>")`. Expired or revoked keys return `403` immediately.

-----

## Audit Export

`GET /finance/audit/export/<account>` returns a single tamper-evident bundle combining position, compliance, attribution, and all 10 stress scenarios:

```json
{
  "account": "ACCT-123",
  "as_of_ts": 1775676905,
  "verified": true,
  "verification_digest": "sha256:...",
  "positions": [...],
  "cash_balance": 500000,
  "public_nav": 507192,
  "private_nav": { "nav": 482395, "pv_capital_calls": 461558, "..." : "..." },
  "futures": { "total_notional": 17675000, "total_mtm_pnl": 175000, "...": "..." },
  "ir_risk": { "fi_count": 1, "total_dv01": -524.21 },
  "total_nav": 933263,
  "risk_snapshot": { "portfolio_var_95": 12.4, "portfolio_mc_t_var_95": 2211, "...": "..." },
  "compliance_report": { "rule_count": 3, "compliance": { "passed": true, "...": "..." } },
  "attribution": { "...": "..." },
  "stress_scenarios": [ { "scenario": "gfc_2008", "pnl": -34600, "...": "..." } ],
  "receipt_chain_digest": "sha256:...",
  "audit_digest": "sha256:..."
}
```

`audit_digest = SHA256(json.encode(bundle))`. Any field alteration invalidates it. Independent auditors can recompute from the replay package at `/finance/export/<account>`.

-----

## Liquidity Forecasting

`GET /finance/liquidity/<account>` projects net cash over 30/90/365-day horizons from futures margins, private flows, and bond coupons.

```json
{
  "current_cash": 3500000,
  "current_initial_margin": 883750,
  "margin_buffer": 2616250,
  "liquidity_score": 100,
  "warnings": [],
  "projected": {
    "days_30": {
      "capital_calls": 0,
      "distributions": 0,
      "bond_coupons": 4500,
      "futures_margin_stress": 176750,
      "net_cash_flow": 4500,
      "projected_cash": 3504500,
      "margin_buffer": 3327750
    }
  }
}
```

Warnings fire when: capital call due within 30 days; projected cash below initial margin; negative margin buffer in 90 days; annual capital calls exceed 50% of current cash.

`liquidity_score` deductions: -30 (cash below initial margin), -40 (30-day cash negative), -20 (30-day calls > 30% of cash), -10 (90-day buffer negative).

-----

## Scenario Analysis

```bash
GET /finance/scenario_at/<account>/<ts_unix>/<scenario>
```

Named scenarios: `equity_down_10`, `equity_up_10`, `market_crash_20`, `bull_case`, `sigma_2`, `sigma_3`, `sigma_4`, `sigma_4_t`, `gfc_2008`, `covid_crash`, `rates_shock`.

Ad-hoc shock map: `AAPL:-0.2,MSFT:-0.1`

```
sigma_2:      -3.4%   (2 standard deviations, Gaussian)
sigma_3:      -5.1%
sigma_4:      -6.8%   (4 standard deviations, Gaussian)
sigma_4_t:    -8.5%   (4 standard deviations, Student-t fat-tail)
gfc_2008:     AAPL -57%, MSFT -44%, default -38%
covid_crash:  AAPL -31%, MSFT -29%, default -34%
rates_shock:  AAPL -18%, MSFT -15%, default -12%
```

Each scenario returns `shocked_positions`, `shocked_nav`, `pnl`, `summary`, and a `scenario_digest` (SHA256 of all inputs and outputs).

-----

## Endpoints

### Write (POST) — requires X-API-Key

```
POST /finance/ingest/fill              Signed execution fill
POST /finance/ingest/cash              Signed cash balance
POST /finance/ingest/order             Signed order for matching
POST /finance/ingest/instrument        Register instrument (equity, bond, option, future)
POST /finance/ingest/corporate_action  Split, reverse split, or dividend
POST /finance/ingest/compliance_rule   Signed compliance rule (admin/risk only)
POST /finance/ingest/cash_flow         Signed private market cash flow
POST /finance/ingest/batch             Array of signed objects (single chain link)
POST /finance/price/claim              Signed price submission
POST /finance/live/price               Fetch and sign a live price feed
POST /finance/match                    Run price-time priority matching
POST /finance/pretrade                 Pre-trade what-if + compliance delta
```

### Read (GET) — open

```
GET /finance/position/<account>                         Live position, NAV, risk, Greeks
GET /finance/compliance/<account>                       Compliance against all active rules
GET /finance/compliance_at/<account>/<ts_unix>          Time-indexed compliance
GET /finance/liquidity/<account>                        30/90/365-day liquidity forecast
GET /finance/audit/export/<account>                     Tamper-evident audit bundle
GET /finance/attribution/<account>                      P&L, cost basis, return
GET /finance/private/nav/<account>                      Private market DCF NAV
GET /finance/orders/<instrument>                        Order book (open/partial/filled)
GET /finance/scenario_at/<account>/<ts_unix>/<scenario> Scenario evaluation
GET /finance/price/aggregate/<symbol>                   Multi-source price consensus
GET /finance/export/<account>                           Full replay package
GET /finance/export_at/<account>/<ts_unix>              Time-indexed replay package
GET /finance/state_at/<account>/<ts_unix>               Time-indexed state
GET /finance/chain/verify                               Receipt chain integrity
GET /health                                             Server health
```

### Admin — requires admin key

```
POST   /admin/api_keys             Create API key
GET    /admin/api_keys             List all keys
DELETE /admin/api_keys/<key_hash>  Revoke key
```

-----

## Receipt Chain

Every request is recorded in an append-only log:

```
chain_digest_n = SHA256(chain_digest_{n-1}, req_digest, res_digest, state_digest)
```

Genesis: `"GENESIS"`. Response headers on every request:

```
X-Qasim-Chain-Digest       current chain head
X-Qasim-Chain-Signature    Ed25519 signature over chain head
X-Qasim-Chain-Public-Key   verifying public key
X-Qasim-Request-Digest     SHA256 of canonical request
X-Qasim-Response-Digest    SHA256 of canonical response
```

`GET /finance/chain/verify` recomputes every digest from stored pre-images and verifies linkage.

-----

## Architecture

```
main.fard
  DB schema, ctx wiring, position cache (mutex), chain witnessing, net.serve

packages/
  qasim_http/       routing, all handlers, RBAC, liquidity, audit export
  qasim_prices/     price loading, staleness, weighted consensus, median, trimmed mean
  qasim_state/      positions, NAV, risk state, VaR (6 methods), Greeks, IR risk,
                    futures MTM, compliance engine, DCF, Monte Carlo
  qasim_scenarios/  scenario evaluation, 10 named scenarios
  qasim_crypto/     Ed25519 chain signing
  qasim_objects/    signed object constructors (fill, cash, order, bond, etc.)
```

All routing lives in `qasim_http`. `main.fard` wires dependencies into a `ctx` record and delegates every request to `qasim_http.handle(req, ctx)`.

-----

## Storage

SQLite, all tables append-only via `INSERT OR IGNORE`:

```
fills           Signed fill records (source of position truth)
cash_objects    Signed cash records
orders          Signed order records
price_claims    Signed multi-source price records
object_store    Unified index by object type
api_keys        RBAC keys (hash only, never raw)
receipt_log     Append-only chain of request/response digests
```

Positions and NAV are computed from fills, not transactions. Corporate actions are stored in `object_store` with `object_type='corporate_action'`.

-----

## Test Suite

```bash
fardrun test --program tests/test_qasim_objects.fard          # 9 tests
fardrun test --program tests/test_qasim_objects_model.fard    # 12 tests
fardrun test --program tests/test_qasim_prices.fard           # 13 tests
fardrun test --program tests/test_qasim_state.fard            # 11 tests
fardrun test --program tests/test_qasim_greeks.fard           # 15 tests
fardrun test --program tests/test_qasim_compliance.fard       # 21 tests
fardrun test --program tests/test_qasim_risk.fard             # 11 tests
fardrun test --program tests/test_qasim_private.fard          # 12 tests
fardrun test --program tests/test_qasim_matching.fard         # 11 tests
fardrun test --program tests/test_qasim_monte_carlo.fard      # 20 tests
```

135 tests, all passing.

-----

## API Documentation

Full OpenAPI 3.0 spec at `docs/openapi.yaml`.

```bash
docker run -p 8080:8080 \
  -e SWAGGER_JSON=/docs/openapi.yaml \
  -v $(pwd)/docs:/docs \
  swaggerapi/swagger-ui

open http://localhost:8080
```

Or paste into https://editor.swagger.io

-----

## Philosophy

Qasim follows FARD principles:

- execution produces artifacts
- artifacts are cryptographically anchored
- computation is deterministic
- verification is first-class

This is not an API. This is a verifiable financial system.