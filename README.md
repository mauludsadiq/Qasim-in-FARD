# Qasim in FARD

Deterministic, verifiable financial state engine built in FARD.

---

## What is Qasim?

Qasim is a cryptographically anchored financial computation system. It ingests
signed transactions, fills, instruments, corporate actions, and multi-source
price feeds, computes recency-weighted consensus prices, derives asset-class-aware
positions and multi-currency NAV, and produces a fully reproducible state digest.

Every output is traceable back to canonical payloads, source data, cryptographic
hashes, and signatures. No hidden state. No ambiguity. No trust assumptions.

The core guarantee: given the same inputs, Qasim will always produce the same
state digest. Any third party can replay the full computation from exported data
and arrive at an identical result.

---

## Quickstart

Generate a signing key and start the server:

  export QASIM_CHAIN_SECRET_HEX=$(openssl rand -hex 32)
export QASIM_ADMIN_KEY_HASH=$(echo -n "apikey:my-dev-key" | sha256sum | awk '{print "sha256:"$1}')
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

  # Futures (E-mini S&P 500)
  curl -X POST /finance/ingest/instrument -H "X-API-Key: <key>" \
  -d '{"payload_json":"{\"instrument_id\":\"ESZ24\",\"asset_class\":\"future\",\"symbol\":\"ES\",\"currency\":\"USD\",\"venue\":\"CME\",\"multiplier\":50,\"expiry_ts_unix\":1778000000}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

### 2. Ingest a fill

  curl -X POST http://0.0.0.0:9801/finance/ingest/fill \
    -H "Content-Type: application/json" \
    -d '{"payload_json":"{\"fill_id\":\"F1\",\"order_id\":\"O1\",\"account\":\"ACCT-123\",\"instrument\":\"AAPL\",\"side\":\"buy\",\"qty\":100,\"price\":170,\"ts_unix\":1731000100}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

### 3. Ingest cash

  curl -X POST http://0.0.0.0:9801/finance/ingest/cash \
    -H "Content-Type: application/json" \
    -d '{"payload_json":"{\"account\":\"ACCT-123\",\"currency\":\"USD\",\"amount\":50000,\"ts_unix\":1731000100}","issuer_pk_hex":"DEV","sig_b64":"DEV"}'

### 4. Submit price claims

  NOW=$(date +%s)
  curl -X POST http://0.0.0.0:9801/finance/price/claim \
    -H "Content-Type: application/json" \
    -d "{\"payload_json\":\"{\\\"symbol\\\":\\\"AAPL/USD\\\",\\\"mid\\\":172,\\\"venue\\\":\\\"NASDAQ\\\",\\\"ts_unix\\\":$NOW}\",\"issuer_pk_hex\":\"DEV\",\"sig_b64\":\"DEV\"}"

### 5. Submit a corporate action (2:1 split)

  curl -X POST http://0.0.0.0:9801/finance/ingest/corporate_action \
    -H "Content-Type: application/json" \
    -d "{\"payload_json\":\"{\\\"action_id\\\":\\\"CA-1\\\",\\\"instrument\\\":\\\"AAPL\\\",\\\"action_type\\\":\\\"split\\\",\\\"ex_ts_unix\\\":$NOW,\\\"effective_ts_unix\\\":$NOW,\\\"ratio_num\\\":2,\\\"ratio_den\\\":1,\\\"cash_amount\\\":0,\\\"currency\\\":\\\"USD\\\"}\",\"issuer_pk_hex\":\"DEV\",\"sig_b64\":\"DEV\"}"

### 6. Fetch a live price from Yahoo Finance

  NOW=$(date +%s)
  ISSUER_SECRET=$(openssl rand -hex 32)
  curl -X POST http://0.0.0.0:9801/finance/live/price \
    -H "Content-Type: application/json" \
    -d "{"symbol":"AAPL/USD","venue":"NASDAQ",\
        "url":"https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d&range=1d",\
        "feed_type":"yahoo","issuer_pk_hex":"DEV","issuer_secret_hex":"$ISSUER_SECRET"}"
  Returns real market price with signed receipt and source_body_digest.

### 7. Submit and match orders

  curl -X POST http://0.0.0.0:9801/finance/ingest/order \
    -d '{"payload_json":"{\"order_id\":\"O-1\",\"account\":\"ACCT-A\",\"instrument\":\"AAPL\",\"side\":\"buy\",\"qty\":100,\"order_type\":\"limit\",\"limit_price\":175,\"ts_unix\":1731000000}","issuer_pk_hex":"pk","sig_b64":"sig"}'

  curl -X POST http://0.0.0.0:9801/finance/match \
    -d '{"instrument":"AAPL","issuer_pk_hex":"SYSTEM"}'

  Returns fills_generated, fill details, prices. Fills appear in /finance/position.

### 8. Query live position

  curl http://0.0.0.0:9801/finance/position/ACCT-123

Response includes positions, cash_balance, nav, nav_usd, fx_rates, risk_state
(with per-position and portfolio VaR), state_digest, and as_of_ts.

### 9. Verify chain integrity

  curl http://0.0.0.0:9801/finance/chain/verify
  {"valid":true,"checked":12,"head":"sha256:..."}

### 10. Export full replay package

  curl http://0.0.0.0:9801/finance/export/ACCT-123

Returns all fills, cash, prices, positions, NAV, risk state, and state digest.
Any party can replay this using POST /finance/replay and arrive at the same
state_digest.

---

## Position Response

A GET /finance/position/<account> response includes:

  {
    account:        "ACCT-123",
    as_of_ts:       1775496255,
    verification_summary: {
      fills:    { checked: 3, valid: 3, invalid: 0, all_valid: true },
      cash:     { checked: 1, valid: 1, invalid: 0, all_valid: true },
      all_valid: true
    },
    positions: [{
      instrument:   "AAPL",
      qty:          200,
      price:        172,
      value:        34400,
      asset_class:  "equity",
      greeks:       null,               -- non-null for options only
      var_95:       12.4,
      var_99:       17.5,
      volatility:   0.0021,
      hvar_95:      8.3,               -- historical VaR 95%
      hvar_99:      14.1,              -- historical VaR 99%
      es_95:        10.2,              -- expected shortfall 95% (CVaR)
      es_99:        16.8               -- expected shortfall 99% (CVaR)
    }],
    cash_balance:   50000,
    nav:            84400,
    nav_usd:        84400,
    fx_rates:       { "EUR": 1.08 },
    risk_state: {
      gross_exposure:         34400,   -- delta-adjusted for options
      net_exposure:           34400,
      long_exposure:          34400,
      short_exposure:         0,
      leverage:               0.41,
      concentration:          0.41,
      portfolio_var_95:       12.4,    -- additive parametric VaR 95%
      portfolio_var_99:       17.5,    -- additive parametric VaR 99%
      portfolio_hvar_95:      8.3,     -- historical VaR 95%
      portfolio_hvar_99:      14.1,    -- historical VaR 99%
      portfolio_es_95:        10.2,    -- expected shortfall 95% (CVaR)
      portfolio_es_99:        16.8,    -- expected shortfall 99% (CVaR)
      portfolio_covar_var_95: 11.1,    -- correlation-aware VaR 95%
      portfolio_covar_var_99: 15.7,    -- correlation-aware VaR 99%
      positions: [{ ... per-position risk ... }]
    },
    state_digest:   "sha256:..."
  }

---

## Core Properties

### Deterministic
Same inputs produce same outputs and same digests. No randomness. Wall clock
is only used for staleness filtering and as_of_ts anchoring — never in the
computation itself.

### Verifiable
All data is hash-addressed, signature-backed, and replayable. The receipt chain
records every request and response in an append-only tamper-evident log.

### Asset-class-aware valuation

  equity        qty x price x multiplier
  fixed_income  qty x (price / 100) x multiplier   (clean price convention)
  fx            qty x price
  option        qty x price x multiplier  (Black-Scholes Greeks computed)
  future        initial_margin = abs(qty) x price x multiplier x margin_rate
                (value = margin posted, not notional)

Futures positions carry additional fields:
  notional         qty x price x multiplier  (gross exposure)
  entry_price      VWAP of buy fills
  mtm_pnl          qty x (current_price - entry_price) x multiplier
  variation_margin max(mtm_pnl, 0)  -- receivable from CCP
  initial_margin   abs(qty) x price x multiplier x initial_margin_rate (default 5%)
  expiry_ts        from instrument metadata

Portfolio futures summary in /finance/position response:
  futures: {
    count:                 1,
    total_notional:        17675000,   -- gross notional exposure
    total_mtm_pnl:         175000,     -- daily mark-to-market P&L
    total_variation_margin: 175000,    -- margin receivable
    total_initial_margin:  883750      -- margin posted
  }

MTM P&L is included in total_nav. Initial margin is tracked in risk_state.

Fixed income positions carry IR risk fields:
  ir_risk: {
    macaulay_duration:  7.81,    -- time-weighted PV / price (years)
    modified_duration:  7.63,    -- mac_dur / (1 + ytm/m)
    convexity:          69.5,    -- second-order price sensitivity
    dv01:              -524.21,  -- $ change per 1bp yield move (negative = long)
    ytm:                0.0475,  -- yield to maturity
    coupon_rate:        0.045,
    face_value:         100,
    clean_price:        98.10
  }

Portfolio IR summary in /finance/position response:
  ir_risk: {
    fi_count:              1,
    total_dv01:           -524.21,   -- portfolio dollar duration
    portfolio_mod_duration: 7.63    -- value-weighted modified duration
  }

Bond instrument registration (dedicated constructor):
  { "instrument_id": "UST10Y", "asset_class": "fixed_income",
    "symbol": "UST10Y", "currency": "USD", "venue": "OTC",
    "multiplier": 1000, "expiry_ts_unix": 1778000000,
    "coupon_rate": 0.045, "face_value": 100,
    "coupon_frequency": 2, "ytm": 0.0475 }

Discounting uses discrete semi-annual compounding: DF = (1 + ytm/m)^(-t*m)
Unregistered instruments default to equity with multiplier 1.

### Recency-weighted consensus

  weight = 300 - (now - ts_unix)   minimum: 1
  weighted_mean = sum(weight x mid) / sum(weight)

The most recent source gets maximum weight (300). Staleness limit is 300s.
Median and trimmed mean (drops outer quartile) are also computed.

### Corporate actions
Splits and reverse splits are ingested as signed events and applied
chronologically when computing positions. The position cache is invalidated
on any new corporate action.

### Multi-currency NAV
FX rates are derived from price claims where symbol matches XXX/USD. Cash
and position values are converted to USD base currency using these rates.
Positions with no FX rate are excluded from nav_usd.

### Risk Suite
Four complementary risk measures per position and portfolio:

Parametric VaR — from realized volatility:
  var_95 = |value| x stddev(returns) x 1.645
  var_99 = |value| x stddev(returns) x 2.326

Historical VaR — exact P&L distribution (252-day lookback):
  Sorted returns, 5th/1st percentile loss. n >= 10 required.

Expected Shortfall / CVaR — average loss beyond VaR threshold:
  es_95 = mean of worst 5% of daily P&L observations
  es_99 = mean of worst 1% of daily P&L observations
  ES >= VaR always. Better tail risk measure for fat-tailed distributions.

Correlation-aware VaR — full covariance matrix (Markowitz):
  portfolio_variance = w^T * Sigma * w
  Uses pairwise return covariances, aligned to 252-day common window.
  Shows diversification benefit vs additive VaR.

Monte Carlo VaR — deterministic simulation (pure-FARD LCG + Box-Muller):
  1000 scenarios, fixed seed=42, fully reproducible across runs
  portfolio_mc_var_95/99, mc_n_sims, mc_seed in every risk_state response

Exposures are delta-adjusted for options (unit_delta x spot x qty x multiplier).

---

## Endpoints

### Ingest (POST)

  /finance/ingest/instrument        Register instrument with asset class
  /finance/ingest/corporate_action  Record split, reverse split, or dividend
  /finance/ingest/tx                Record a transaction
  /finance/ingest/cash              Record a cash balance
  /finance/ingest/order             Record an order
  /finance/ingest/fill              Record an execution fill
  /finance/price/claim              Submit a signed price
  /finance/live/price               Fetch and sign a live price feed
  /finance/ingest/compliance_rule   Register a signed compliance rule
  /finance/ingest/cash_flow         Register a signed private market cash flow
  /finance/ingest/instrument        Register instrument (equity, option, future, bond)
  /finance/ingest/order             Submit a signed order for matching
  /finance/ingest/batch             Ingest array of signed objects (single chain link)
  /finance/match                    Run price-time priority matching for an instrument
  /finance/replay                   Replay state from supplied data

All mutating endpoints require a non-empty body. Ed25519 signatures are verified
before storage. Records are immutable — first write wins (INSERT OR IGNORE).
Future-dated ts_unix values are rejected. URL-encoded path parameters are decoded.

### Query (GET)

  /finance/export/<account>                        Full replay package
  /finance/price/aggregate/<symbol>                Multi-source price consensus
  /finance/state_at/<account>/<ts_unix>            Time-indexed state
  /finance/export_at/<account>/<ts_unix>           Time-indexed export
  /finance/state_payload/<account>/<ts_unix>       Raw state digest payload
  /finance/scenario_at/<account>/<ts_unix>/<scenario>     Scenario evaluation
  /finance/position/<account>                      Live position, NAV, VaR, Greeks, verification
  /finance/attribution/<account>                   Performance attribution (P&L, cost basis, return)
  /finance/compliance/<account>                    Compliance check against all active rules
  /finance/compliance_at/<account>/<ts_unix>       Time-indexed compliance check
  /finance/pretrade                                Pre-trade what-if + compliance delta
  /finance/private/nav/<account>                   Private market DCF NAV
  /finance/orders/<instrument>                     View orders by instrument (open/partial/filled)
  /finance/chain/verify                            Chain integrity check
  /health                                          Server health

---

## Price Consensus

### Staleness
MAX_PRICE_AGE = 86400 seconds (1 day). A price is valid at time t only if
ts_unix <= t and (t - ts_unix) <= 86400. Stale prices are excluded from
valuation. Future-dated prices are rejected at ingest. Historical VaR uses
all_price_rows (no staleness filter) to preserve full return history.

### Aggregation output
  mean           unweighted average
  weighted_mean  recency-weighted average (used as consensus_price)
  median         middle value of sorted price series
  trimmed_mean   drops outer quartile, averages remainder (null if n < 4)
  variance       population variance
  outliers       sources where |mid - mean|^2 > 4 * variance

---

## Canonical State Model

  state_digest = SHA256(
    account, as_of_ts,
    fill_digests, cash_digests, price_digests,
    positions, nav, risk_state
  )

Positions include: qty, price, value, asset_class, greeks (options only).
Risk state includes: gross/net/long/short exposure, leverage, concentration,
portfolio_var_95/99 (additive), portfolio_hvar_95/99 (historical exact),
portfolio_covar_var_95/99 (correlation-aware covariance matrix VaR).

Live /finance/position/ passes as_of_ts = server wall clock, making every
snapshot uniquely time-anchored. Use /finance/state_at/ for reproducible
digests at a specific historical timestamp.

---

## Time-Indexed State

  state(t) = f(fills <= t, prices <= t)

All _at endpoints accept a ts_unix cutoff. Only data at or before t is used.
No forward-looking data is ever used.

---

## Scenario Analysis

Scenarios apply deterministic shocks to base state without modifying it.

  GET /finance/scenario_at/<account>/<ts_unix>/<scenario>

Instrument shock map (ad hoc):  AAPL:-0.2,MSFT:-0.1
Named scenarios:

  Directional:    equity_down_10, equity_up_10, market_crash_20, bull_case
  Single name:    tech_selloff, single_name_gap_down
  Sigma shocks:   sigma_2, sigma_3, sigma_4, sigma_4_t
  Historical:     gfc_2008, covid_crash, rates_shock

Sigma shocks use fixed per-instrument volatility estimates:
  sigma_2:    -3.4%   (2 standard deviations)
  sigma_3:    -5.1%   (3 standard deviations)
  sigma_4:    -6.8%   (4 standard deviations, Gaussian)
  sigma_4_t:  -8.5%   (4 standard deviations, Student-t fat-tail adjusted)

Historical crisis scenarios:
  gfc_2008:     AAPL -57%, MSFT -44%, default -38%
  covid_crash:  AAPL -31%, MSFT -29%, default -34%
  rates_shock:  AAPL -18%, MSFT -15%, default -12%

Each scenario returns:
  shocked_positions  -- per-instrument shock, base/shocked price, pnl
  shocked_nav        -- portfolio NAV after shock
  pnl                -- total portfolio P&L
  summary            -- { base_nav, shocked_nav, total_pnl, pnl_pct,
                          max_single_loss, positions_shocked }
  scenario_digest    -- SHA256 of all scenario inputs and outputs

Stress test results (ACCT-123, illustrative):
  sigma_4:    -4.1%    (Gaussian 4-sigma)
  sigma_4_t:  -5.2%    (fat-tail adjusted, +26% premium)
  covid_crash: -18.8%
  gfc_2008:   -34.6%   (binding tail constraint)

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

Supported feed_types: simple_json, yahoo (Yahoo Finance via User-Agent header).

Live feed signing: POST /finance/live/price fetches an external URL, builds
a canonical receipt, and signs it with the caller's Ed25519 key
(issuer_secret_hex). Verifiable against issuer_pk_hex with no shared secret.

---

## In-Memory Position Cache

Positions are cached in a process-level mutex keyed by:

  SHA256(account + fill_digests + cash_digests + price_digests + ca_digests)

Cache hits skip position recomputation entirely. Any new fill, cash entry,
price claim, or corporate action changes the key and triggers recomputation.
Cache is correct by construction: same key always maps to same positions.

---

## Architecture

  main.fard
    DB schema, ctx wiring, position cache, chain witnessing, net.serve

  packages/
    qasim_http/      routing, all handlers, request/response shaping
    qasim_prices/    price loading, staleness, aggregation, weighted consensus,
                     median, trimmed mean
    qasim_state/     positions, NAV, risk state, VaR, corporate actions, FX
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
  object_store    Unified index by object type (instruments, prices, CAs, fills)
  receipt_log     Append-only chain of request/response digests

Positions and NAV are computed from fills, not tx.
Corporate actions are stored in object_store with object_type='corporate_action'.

---

## Test Suite

  fardrun test --program tests/test_qasim_objects.fard        9 tests
  fardrun test --program tests/test_qasim_objects_model.fard  12 tests
  fardrun test --program tests/test_qasim_prices.fard         13 tests
  fardrun test --program tests/test_qasim_state.fard          11 tests
  fardrun test --program tests/test_qasim_greeks.fard         15 tests
  fardrun test --program tests/test_qasim_compliance.fard     21 tests
  fardrun test --program tests/test_qasim_risk.fard           11 tests
  fardrun test --program tests/test_qasim_private.fard        12 tests
  fardrun test --program tests/test_qasim_matching.fard       11 tests
  fardrun test --program tests/test_qasim_monte_carlo.fard    12 tests
  117 tests total, all passing

---

## Future Extensions

- Integrations (Bloomberg, custodians, exchanges)
- XBRL / regulatory export formats with embedded digests
- Helm chart for Kubernetes deployment
- Correlation-aware Monte Carlo (Cholesky decomposition)
- Stress testing with shocked covariance matrix and Greeks re-computation

---

## Performance Attribution

GET /finance/attribution/<account> returns per-position P&L attribution:

  {
    beginning_nav:    2026,
    current_nav:      5152,
    attribution: {
      portfolio_return: 0.0237,
      total_pnl:        48,
      positions: [{
        instrument:     "AAPL",
        avg_cost:       171,
        current_price:  173,
        unrealized_pnl: 48,
        realized_pnl:   0,
        total_pnl:      48,
        contribution:   0.0237
      }]
    }
  }

cost_basis = weighted average fill price (buys only)
realized_pnl = FIFO P&L on closed positions
contribution = position_pnl / beginning_nav
portfolio_return = total_pnl / beginning_nav

---

## Batch Ingest

POST /finance/ingest/batch accepts an array of signed objects:

  {
    "items": [
      { "object_type": "fill", "payload_json": "...", "issuer_pk_hex": "...", "sig_b64": "..." },
      { "object_type": "cash", ... },
      { "object_type": "price_claim", ... }
    ]
  }

Each item is verified and routed by object_type. All accepted items share a
single chain link. Returns { accepted, rejected, results } with per-item status.
Supports: fill, cash, price_claim, instrument, corporate_action, order.

---

## Pre-Trade What-If

POST /finance/pretrade simulates a proposed order without writing to DB:

  { "account": "ACCT-123", "instrument": "AAPL", "side": "buy", "qty": 100, "price": 172 }

Returns current state, hypothetical state (with synthetic fill applied), and delta:

  delta: { nav, cash_balance, gross_exposure, leverage, concentration }

Full risk suite (parametric VaR, historical VaR) computed on both states.
Useful for compliance checks, position limits, and risk budgeting before execution.

---

## Compliance Rules Engine (18 Rule Types)

POST /finance/ingest/compliance_rule stores a signed rule with severity and timestamps:

  {
    "rule_id": "R1", "account": "ACCT-123",
    "rule_type": "max_position_size",
    "params": {"instrument": "AAPL", "max_value": 10000},
    "severity": "hard",
    "effective_ts": 0, "expiry_ts": 0
  }

Supported rule types (18 total): max_position_size, max_concentration, max_leverage,
max_gross_exposure, max_portfolio_var_95/99, min_cash_pct, max_position_qty,
max_asset_class_exposure, instrument_blacklist, max_delta_exposure, max_vega,
max_portfolio_covar_var_95/99, max_es_95/99, max_illiquid_pct, max_capital_call_exposure,
max_margin_utilization.

Each breach includes a suggested_action (e.g. "reduce AAPL by 1152").
Rules with account="*" apply globally across all accounts.
evaluate_compliance returns hard_breaches, warnings, and info separately.
passed=true only when zero hard breaches.

GET /finance/compliance/<account> and GET /finance/compliance_at/<account>/<ts>
return the full compliance state with verification_summary.

POST /finance/pretrade returns compliance_delta: new_breaches and resolved_breaches
after the proposed trade. trade_blocked=true only for new hard breaches.

---

## Option Greeks (Black-Scholes)

Register an option instrument with strike, implied_vol, option_type, risk_free_rate:

  POST /finance/ingest/instrument
  { "instrument_id": "AAPL-CALL-260", "asset_class": "option",
    "symbol": "AAPL", "strike": 260, "implied_vol": 0.25,
    "option_type": "call", "risk_free_rate": 0.05,
    "expiry_ts_unix": 1778000000, "multiplier": 100 }

Positions with asset_class="option" include a greeks field:

  greeks: {
    delta: 99.18,   -- position delta (qty x multiplier x unit_delta)
    gamma: 0.00495,
    vega:  40.53,   -- per 1% vol move
    theta: -0.173,  -- per calendar day
    rho:   611.6,   -- per 1% rate move
    unit_greeks: { delta: 0.9918, gamma: 0.0000495, ... }
  }

Normal CDF via Abramowitz-Stegun 5-term Horner approximation.
time_to_expiry computed from expiry_ts_unix - as_of_ts in years.

---

## Signature Verification on Read

All major query endpoints verify Ed25519 signatures on every object fetched
from the database before using it in computation. Tampered or missing-sig
objects are excluded silently. Each response includes:

  verification_summary: {
    fills: { checked: 3, valid: 3, invalid: 0, all_valid: true },
    cash:  { checked: 1, valid: 1, invalid: 0, all_valid: true },
    all_valid: true
  }

Endpoints with verification: /position, /compliance, /compliance_at,
/attribution, /pretrade.

---

## Private Markets

POST /finance/ingest/cash_flow ingests a signed cash flow schedule entry:

  {
    "flow_id": "CF1", "asset_id": "PE-FUND-1",
    "account": "ACCT-123", "flow_type": "distribution",
    "amount": 1000000, "currency": "USD",
    "expected_ts": 1807041600
  }

flow_type: distribution | capital_call | fee
capital_calls and fees are subtracted from NAV; distributions are added.

GET /finance/private/nav/<account> returns DCF NAV at 8% continuous discount:

  private_nav: {
    nav:              482395.26,   -- net present value
    pv_distributions: 943953.43,   -- PV of future distributions
    pv_capital_calls: 461558.17,   -- PV of unfunded commitments
    pv_fees:          0,
    flow_count:       2,
    discount_rate:    0.08,
    as_of_ts:         1775605701
  }

Past flows (expected_ts <= as_of_ts) are excluded automatically.

Illiquidity compliance rules:
  max_illiquid_pct          {max_pct}   -- private_nav / total_nav limit
  max_capital_call_exposure {max_value} -- PV unfunded commitments limit
  max_margin_utilization    {max_pct}   -- variation_margin / initial_margin limit
                                           fires when futures MTM gains exceed
                                           max_pct% of initial margin posted

These rules are evaluated in /finance/compliance using live risk state including
futures margin data, private DCF NAV, and full VaR/ES/Greeks.

---

## Matching Engine

POST /finance/match runs price-time priority (FIFO) matching for an instrument:

  { "instrument": "AAPL", "issuer_pk_hex": "DEV" }

Matching rules:
- Limit orders match when buy_limit >= sell_limit
- Market orders match against any resting order
- Match price = resting (maker) order price
- Partial fills supported — order status: open | partial | filled
- Both buy and sell fills written as signed objects to fills + object_store

GET /finance/orders/<instrument> returns order book with fill status:

  orders: [{
    order_id:   "O-BUY-1",
    account:    "ACCT-A",
    side:       "buy",
    qty:        100,
    limit_price: 175,
    filled_qty: 60,
    status:     "partial"
  }]

Network test: buy 100 @ 175 vs sell 60 @ 173 → 2 fills at 173, qty=60.
Buy order remains partial (40 unfilled). Fills appear in /finance/position.

---

## Monte Carlo VaR

Four VaR methods in every /finance/position response:

  portfolio_mc_var_95/99         Gaussian independent (baseline)
  portfolio_mc_chol_var_95/99    Gaussian Cholesky (correlated)
  portfolio_mc_t_var_95/99       Student-t Cholesky (fat-tail, nu=4)
  portfolio_covar_var_95/99      Analytic covariance (Markowitz)

Pure-FARD LCG (no external PRNG, fully deterministic):
  lcg_next(state) = |state * 6364136223846793005 + 1442695040888963407|
  Box-Muller: N(0,1) from two uniform LCG draws
  Student-t:  t = Z / sqrt(Chi2(nu)/nu), Chi2 via sum of nu squared normals

Cholesky decomposition (pure FARD matrix library):
  build_cov_matrix: n x n covariance matrix from aligned 252-day returns
  cholesky(Sigma, n): lower triangular L where Sigma = LL^T
  Correlated draw: x = L * z where z ~ N(0,I) or t(nu)

All methods: n_sims=1000, seed=42, fully reproducible and auditable.
mc_t_nu=4 (standard for financial returns — heavier tails than Gaussian).

Illustrative results (ACCT-123):
  gaussian independent:    299    (uncorrelated, underestimates)
  analytic covar:         1705    (correlation-aware)
  gaussian cholesky:      1789    (MC correlated)
  student-t cholesky:     2211    (+24% fat-tail premium at 95%)
  student-t 99%:          3986    (+57% fat-tail premium at 99%)

---

## Authentication & RBAC

All write endpoints require an `X-API-Key` header. Read endpoints are open.

### Roles

  admin     -- full access: ingest, match, compliance rules, read, key management
  trader    -- ingest + match + read
  risk      -- manage compliance rules + read
  readonly  -- read only

### Bootstrap

Set `QASIM_ADMIN_KEY_HASH` at startup (SHA256 of `apikey:<your-key>`):

  export ADMIN_KEY="$(openssl rand -hex 32)"
  export QASIM_ADMIN_KEY_HASH="$(echo -n "apikey:${ADMIN_KEY}" | sha256sum | awk '{print "sha256:"$1}')"
  fardrun run --program main.fard --out /tmp/qasim

The raw key is never stored — only its SHA256 hash.

### Key Management

  POST /admin/api_keys    -- create a key (admin only)
  GET  /admin/api_keys    -- list all keys (admin only)

  curl -X POST /admin/api_keys \
    -H "X-API-Key: <admin-key>" \
    -d '{"label":"trader-desk","role":"trader","key":"<key-value>"}'

### Endpoint Permissions

  /finance/ingest/*          -- write  (admin, trader)
  /finance/match             -- match  (admin, trader)
  /finance/pretrade          -- write  (admin, trader)
  /finance/ingest/compliance_rule -- manage_rules (admin, risk)
  /finance/position/*        -- open   (no auth required)
  /finance/compliance/*      -- open
  /finance/attribution/*     -- open
  /finance/private/nav/*     -- open

### Helm Deployment with RBAC

  ADMIN_KEY="$(openssl rand -hex 32)"
  ADMIN_HASH="$(echo -n "apikey:${ADMIN_KEY}" | sha256sum | awk '{print "sha256:"$1}')"
  helm install qasim ./helm/qasim \
    --set secret.chainSecretHex=$(openssl rand -hex 32) \
    --set secret.adminKeyHash="${ADMIN_HASH}"

---

## API Documentation

The full OpenAPI 3.0 spec is at `docs/openapi.yaml`.

View interactively in Swagger UI:

  docker run -p 8080:8080 \
    -e SWAGGER_JSON=/docs/openapi.yaml \
    -v $(pwd)/docs:/docs \
    swaggerapi/swagger-ui

  open http://localhost:8080

Or paste the raw file into https://editor.swagger.io

---

## Philosophy

Qasim follows FARD principles:

- execution produces artifacts
- artifacts are cryptographically anchored
- computation is deterministic
- verification is first-class

This is not an API. This is a verifiable financial system.
