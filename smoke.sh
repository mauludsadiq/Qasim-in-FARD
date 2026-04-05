#!/usr/bin/env bash
set -euo pipefail

OPENSSL_BIN=/opt/homebrew/opt/openssl@3/bin/openssl
BASE_URL=http://127.0.0.1:9801
WORK=/tmp/qasim_fard_smoke
rm -rf "$WORK"
mkdir -p "$WORK"

"$OPENSSL_BIN" genpkey -algorithm Ed25519 -out "$WORK/sk.pem" >/dev/null 2>&1
PUBHEX=$("$OPENSSL_BIN" pkey -in "$WORK/sk.pem" -pubout -outform DER | tail -c 32 | xxd -p -c 256)

TX1='{"account":"ACCT-123","id":"T-1","instrument":"AAPL","price":170.5,"qty":10,"side":"buy","ts_unix":1731000100}'
printf '%s' "$TX1" > "$WORK/tx1.json"
"$OPENSSL_BIN" pkeyutl -sign -inkey "$WORK/sk.pem" -rawin -in "$WORK/tx1.json" -out "$WORK/tx1.sig" >/dev/null 2>&1
TX1SIG=$(base64 < "$WORK/tx1.sig" | tr -d '\n')
jq -n \
  --arg id "T-1" \
  --arg account "ACCT-123" \
  --arg instrument "AAPL" \
  --arg side "buy" \
  --argjson qty 10 \
  --argjson price 170.5 \
  --argjson ts_unix 1731000100 \
  --arg issuer "$PUBHEX" \
  --arg sig "$TX1SIG" \
  --arg payload "$TX1" \
  '{id:$id,account:$account,instrument:$instrument,side:$side,qty:$qty,price:$price,ts_unix:$ts_unix,issuer_pk_hex:$issuer,sig_b64:$sig,payload_json:$payload}' \
| curl -sS -X POST "$BASE_URL/finance/ingest/tx" -H 'content-type: application/json' --data-binary @- > "$WORK/tx1.out.json"

TX2='{"account":"ACCT-123","id":"T-2","instrument":"AAPL","price":172,"qty":4,"side":"sell","ts_unix":1731000110}'
printf '%s' "$TX2" > "$WORK/tx2.json"
"$OPENSSL_BIN" pkeyutl -sign -inkey "$WORK/sk.pem" -rawin -in "$WORK/tx2.json" -out "$WORK/tx2.sig" >/dev/null 2>&1
TX2SIG=$(base64 < "$WORK/tx2.sig" | tr -d '\n')
jq -n \
  --arg id "T-2" \
  --arg account "ACCT-123" \
  --arg instrument "AAPL" \
  --arg side "sell" \
  --argjson qty 4 \
  --argjson price 172 \
  --argjson ts_unix 1731000110 \
  --arg issuer "$PUBHEX" \
  --arg sig "$TX2SIG" \
  --arg payload "$TX2" \
  '{id:$id,account:$account,instrument:$instrument,side:$side,qty:$qty,price:$price,ts_unix:$ts_unix,issuer_pk_hex:$issuer,sig_b64:$sig,payload_json:$payload}' \
| curl -sS -X POST "$BASE_URL/finance/ingest/tx" -H 'content-type: application/json' --data-binary @- > "$WORK/tx2.out.json"

QUOTE='{"mid":171,"symbol":"AAPL/USD","ts_unix":1731000120,"venue":"NASDAQ"}'
printf '%s' "$QUOTE" > "$WORK/quote.json"
"$OPENSSL_BIN" pkeyutl -sign -inkey "$WORK/sk.pem" -rawin -in "$WORK/quote.json" -out "$WORK/quote.sig" >/dev/null 2>&1
QUOTESIG=$(base64 < "$WORK/quote.sig" | tr -d '\n')
jq -n \
  --arg symbol "AAPL/USD" \
  --argjson mid 171 \
  --argjson ts_unix 1731000120 \
  --arg venue "NASDAQ" \
  --arg issuer "$PUBHEX" \
  --arg sig "$QUOTESIG" \
  --arg payload "$QUOTE" \
  '{symbol:$symbol,mid:$mid,ts_unix:$ts_unix,venue:$venue,issuer_pk_hex:$issuer,sig_b64:$sig,payload_json:$payload}' \
| curl -sS -X POST "$BASE_URL/finance/price/claim" -H 'content-type: application/json' --data-binary @- > "$WORK/quote.out.json"

curl -sS "$BASE_URL/finance/position/ACCT-123" > "$WORK/pos1.json"
curl -sS "$BASE_URL/finance/position/ACCT-123" > "$WORK/pos2.json"

echo "=== tx1 ==="
cat "$WORK/tx1.out.json"
echo
echo "=== tx2 ==="
cat "$WORK/tx2.out.json"
echo
echo "=== quote ==="
cat "$WORK/quote.out.json"
echo
echo "=== position ==="
cat "$WORK/pos1.json" | python3 -m json.tool
echo "=== determinism ==="
shasum -a 256 "$WORK/pos1.json" "$WORK/pos2.json"
